# WKWebViewでWebページを切り取ってウィジェットに貼る――Portholeの技術設計

macOSの通知センターウィジェットに「Webページの一部」をそのまま表示したい、という欲求はずっとあった。RSSリーダーでも天気アプリでもなく、任意のページの任意の領域を、そのままスナップショットとして貼り付けたい。それがPortholeを作った動機だ。

本稿では、Portholeがどのような技術的判断でその機能を実現しているかを解説する。

---

## 全体像：3ターゲット構成

Portholeは3つのビルドターゲットで構成されている。

```
Porthole          ← メニューバーアプリ（キャプチャ担当）
PortholeShared    ← アプリとウィジェットで共有するSwiftファイル群
PortholeWidget    ← WidgetKit拡張（表示担当）
```

アプリとウィジェットはプロセスが分離されているため、データの受け渡しにはApp Group（`group.com.dmng.porthole`）を使う。アプリがキャプチャした画像をApp Groupコンテナに書き込み、ウィジェットがそれを読み出して描画する、という一方通行の設計だ。

---

## クリップモデル

管理の単位は「クリップ（Clip）」と呼ぶ。

```swift
struct Clip: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var source: Source        // URLまたはローカルHTML
    var clipMode: ClipMode    // 矩形またはCSSセレクタ
    var renderViewport: CGSize
    var refreshSeconds: TimeInterval
    var captureDelaySeconds: TimeInterval
    var lastUpdated: Date?
    var dominantColor: ClipColor?
}
```

`source`と`clipMode`はどちらもenumで、値として関連データを持つ。

```swift
enum Source: Codable, Hashable {
    case remote(URL)
    case localBookmark(htmlBookmark: Data, accessRootBookmark: Data)
}

enum ClipMode: Codable, Hashable {
    case rect(ClipRect)
    case selector(String)
    case selectorWithFallbackRect(selector: String, fallbackRect: ClipRect)
}
```

ローカルHTMLはセキュリティスコープブックマーク（`Data`）として保存するため、アプリを再起動してもファイルを再選択せずに読み込める。

クリップ一覧はApp Group内の `registry.json` に保存する。`ClipStore`がその読み書きを担い、`JSONEncoder/JSONDecoder`でアトミックに永続化する。アプリとウィジェット拡張の両方が同じ`ClipStore`実装を参照するので、`PortholeShared`ターゲットに置いている。

---

## スナップショットキャプチャの仕組み

Portholeの核心は`SnapshotCapturer`だ。

### オフスクリーンWKWebView

通常のアプリでWebViewといえば画面に表示するものだが、ここでは画面外に置いて「描画専用マシン」として使う。

```swift
hostWindow = NSWindow(
    contentRect: CGRect(x: -20_000, y: -20_000, width: 1200, height: 900),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
hostWindow.collectionBehavior = [.stationary, .ignoresCycle]
hostWindow.contentView?.addSubview(webView)
```

座標を画面外（-20000, -20000）に置き、`collectionBehavior`で Mission Control・Exposé・Cmd+\` のサイクル対象から除外する。ウィンドウ自体はメモリ上に存在し続けるが、ユーザーには見えない。

WebViewをオフスクリーンウィンドウに乗せないと`takeSnapshot`が正しく動かないのが理由だ。`NSView`として画面の描画パイプラインに乗る必要がある。

### ページロード待機チェーン

単純に`webView.load()`してすぐスナップショットを撮っても、まだレンダリングが終わっていないことが多い。そのため、完了確認を段階的に行う。

```
1. WKNavigationDelegate.didFinish（ナビゲーション完了）
2. document.readyState === "complete"（DOMパース完了）
3. document.fonts.status === "loaded"（フォント読み込み完了）
4. 可視画像のcomplete判定（画像読み込み完了）
5. getBoundingClientRect() + resize Event（強制レイアウト）
6. captureDelaySeconds 待機（非同期コンテンツ向けの猶予時間）
```

これらをすべてSwift Concurrencyの`async/await`でチェーンしている。各ステップには個別にタイムアウトを設けてある。

### ローカルHTMLのカスタムURLスキーム

サンドボックス環境ではローカルHTMLを`file://`で直接ロードすると相対パス参照が制限される。そのため、`WKURLSchemeHandler`を独自実装した`LocalHTMLSchemeHandler`を挟み、`porthole-local://localhost/`というカスタムスキームでコンテンツを配信している。セキュリティスコープブックマークで解決したファイルアクセス権は、このハンドラ内で使用する。

### CSSセレクタによるクリップ

矩形（x/y/幅/高さ）の固定指定に加えて、CSSセレクタでHTML要素を指定する「セレクタモード」がある。

```javascript
const element = document.querySelector(selectorValue);
const rect = element.getBoundingClientRect();
return JSON.stringify({
    x: Math.max(0, rect.x + window.scrollX),
    y: Math.max(0, rect.y + window.scrollY),
    width: Math.max(1, rect.width),
    height: Math.max(1, rect.height)
});
```

要素のビューポート相対座標をスクロール量で補正してドキュメント絶対座標に変換し、それを撮影矩形として使う。セレクタが見つからない場合はフォールバック矩形（`selectorWithFallbackRect`）に自動的に切り替わる。

### 撮影矩形がビューポート外にある場合のスクロール制御

指定した矩形がビューポート外にある場合、JavaScriptで`window.scrollTo()`を呼んでから撮影する。

```javascript
window.scrollTo(nextX, nextY);
```

スクロール後のオフセットを`window.scrollX / scrollY`で読み取り、撮影矩形の座標をオフセット分だけ補正することで、スクロールした先の正しい座標を`takeSnapshot(rect:)`に渡せる。

### ファミリーサイズへのリサイズ

`WKWebView.takeSnapshot`で得た`NSImage`を、Small / Medium / Large の3サイズにリサイズしてApp Groupコンテナに保存する。

```swift
for family in SnapshotFamily.allCases {
    let resizedImage = image.resizedToFit(maxSize: family.pointSize)
    let data = resizedImage.pngData
    try data.write(to: snapshotURL, options: .atomic)
}
```

リサイズ時はアスペクト比を維持したまま、各ファミリーサイズの枠内に収まるように縮小している。つまりセンタートリミングや「アスペクトフィル＋中央クロップ」は行わず、必要に応じて余白が出る前提のアスペクトフィット相当の挙動である。

### 代表色の抽出

ウィジェット背景色として、スナップショット外周から代表色を抽出する。端部のピクセルをサンプリングして4ビット（16段階）に量子化してバケット集計し、最多のバケットの平均色を使う。中央ではなく「外周」を見るのは、コンテンツの色をそのまま背景に出してウィジェット全体を自然に見せるためだ。

---

## 自動更新スケジューラ

`RefreshScheduler`は`actor`として実装されており、次の更新期限が最も近いクリップを見つけ、`Task.sleep`で待機してからコールバックを呼ぶ。

```swift
actor RefreshScheduler {
    private var refreshTask: Task<Void, Never>?

    func schedule(clips: [Clip], onDue: @escaping @MainActor @Sendable (UUID) -> Void) {
        refreshTask?.cancel()
        guard let nextRefresh = Self.findNextRefresh(in: clips, at: Date()) else {
            refreshTask = nil
            return
        }
        refreshTask = Task {
            await Self.sleepUntil(nextRefresh.date)
            guard !Task.isCancelled else { return }
            await onDue(nextRefresh.clipId)
        }
    }
}
```

アプリが起動していない間はウィジェットのタイムライン更新に依存するが、スナップショットの再生成はしない。起動直後とMacのスリープ解除時に期限切れクリップをまとめて撮り直す。

---

## WidgetKit側の設計

### AppIntentConfigurationによるクリップ選択

WidgetKitの設定UIでどのクリップを表示するかを選ぶために、`AppIntentConfiguration`と`SelectClipIntent`を使う。

```swift
struct ClipEntityQuery: EntityQuery {
    func suggestedEntities() async throws -> [ClipEntity] {
        let clips = (try? ClipStore.shared.loadClips()) ?? []
        return clips.map(ClipEntity.init(clip:))
    }
}
```

`ClipStore.shared.loadClips()`はウィジェット拡張からも呼べる。App Groupコンテナの`registry.json`を読むだけなのでプロセス分離の影響を受けない。

### タイムラインポリシー

```swift
let nextUpdate = Date().addingTimeInterval(entry.refreshSeconds)
return Timeline(entries: [entry], policy: .after(nextUpdate))
```

選択クリップの`refreshSeconds`をそのままWidgetKitのタイムラインポリシーに渡す。macOSはバッテリーやシステム負荷に応じて更新を間引くことがあるため、アプリ側の`RefreshScheduler`と二重に管理している。

### ディープリンクによるソースURL起動

ウィジェットのクリックURLは`porthole://open-source/<clip-id>`に設定してある。

```swift
var widgetURL: URL? {
    guard let clipId = entry.clipId else { return nil }
    return URL(string: "porthole://open-source/\(clipId.uuidString)")
}
```

アプリ側の`URLRouter`がこのURLを受け取り、クリップIDからリモートURLを解決して`NSWorkspace.shared.open()`で既定ブラウザを開く。

---

## 振り返り

実装を通じて一番苦労したのは、WebViewのレンダリング完了タイミングの検出だ。`didFinish`コールバックだけでは画像もフォントもまだロードされていない状態でスナップショットを撮ってしまう。段階的なポーリングとタイムアウトを重ねてようやく安定した。

「それって結局ブラウザをヘッドレスで動かしているようなもの」というのはその通りで、WKWebViewはAppleのサンドボックスモデルで動くHeadlessブラウザとして機能している。Puppeteerやheadless Chromiumと同じ発想だが、macOSのApp Sandboxと共存できる点と、WidgetKitとのApp Groupによるデータ共有が自然に組み合わさる点が利点だ。

コードはGitHubで公開している。

- **GitHub**: [github.com/Nihondo/Porthole](https://github.com/Nihondo/Porthole)
