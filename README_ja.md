# Porthole

Porthole は、任意のWebページやローカルHTMLの一部分をmacOSウィジェットへ表示するためのメニューバー常駐アプリです。

## 現在の状態

Porthole は M9 のローカライズ・仕上げ段階です。

- 本体アプリ、共有Swift、Widget拡張の3領域を作成済み
- App Group: `group.com.dmng.porthole`
- Bundle ID: `com.dmng.porthole.Porthole` / `com.dmng.porthole.Porthole.PortholeWidget`
- 本体アプリは初回起動時にサンプルクリップを作成
- 設定画面でクリップの追加・削除・選択・編集・保存が可能
- 名前、読み込み元、viewport、更新間隔、クリッピング方式、矩形座標、CSSセレクタを編集可能
- 読み込み元は remote URL とローカルHTMLを選択可能
- ローカルHTMLは `NSOpenPanel` で選択し、security-scoped bookmark として保存
- 埋め込み `WKWebView` プレビュー上で矩形をドラッグ移動・右下ハンドルでリサイズ可能
- プレビュー上の要素をクリックしてCSSセレクタを取得可能
- メニューまたは設定画面の **クリップを最新化** で、選択中の remote URL / ローカルHTML クリップを `WKWebView` で撮影
- App Group の `snapshots/` へ small / medium / large PNG を保存
- 本体アプリ起動中は `refreshSeconds` に基づいて定期撮影
- アプリ起動時とシステム復帰時に、最終更新から更新間隔を超えたクリップを再撮影
- Widget編集画面で表示対象クリップを選択可能
- Widget は選択クリップのPNGがあれば画像表示し、未撮影時はローカライズ済みプレースホルダーを表示
- Widget の timeline policy は選択クリップの更新間隔に合わせて再読み込み
- remote URL クリップのWidgetをクリックすると、デフォルトブラウザで元URLを開く
- メニューからログイン時起動を切り替え可能
- アプリ本体とWidgetのユーザー向け文字列は日本語・英語に対応

## メニュー

- **Porthole 設定...**: 設定画面を開きます。
- **クリップを最新化**: 現在選択中の保存済みクリップを撮影し、Widget用PNGを更新します。
- **ログイン時にアプリを起動**: macOSのログイン項目登録を切り替えます。
- **Porthole について...**: 標準のAbout画面を開きます。
- **終了**: アプリを終了します。

## ビルド

署名なしのローカル確認:

```sh
rtk xcodebuild -project Porthole.xcodeproj -scheme Porthole -destination 'platform=macOS' -derivedDataPath /tmp/PortholeDerived CODE_SIGNING_ALLOWED=NO build
```

実機で App Group を使って動かす場合は、`Configurations/DevelopmentTeam.local.xcconfig` を作成し、Apple Developer Team ID を設定してください。

```xcconfig
DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
```

## 制約

WidgetKit の制約により、ウィジェット内で `WKWebView` はホストできません。本体アプリがPNGスナップショットを作成し、ウィジェットはその画像を表示します。本体アプリが起動していない間、スナップショットは更新されません。

M8後の方針として、Widget上のボタンアクションや擬似操作は削除しています。remote URL クリップのWidgetクリック時はデフォルトブラウザで元URLを開きます。
