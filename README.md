# Liner

Liner は、多数のローカル音楽ファイルのタグをまとめて整理するための macOS ネイティブアプリです。

中心にある考え方は、音楽メタデータをスプレッドシートのような表で編集し、貼り付け、一括編集、連番生成、ファイル名生成、カバーアート設定をまとめて扱えるようにすることです。

## コンセプト

Liner は、Windows 向けタグエディタである STEP改 / STEP_K の実用的なワークフロー、とりわけ「表計算ソフト風に大量のタグを編集できる」という優れた体験から着想を得ています。

その思想に敬意を払いながら、Liner は macOS 専用アプリとして独自に設計・開発します。STEP改 / STEP_K の公式 Mac 版、移植版、派生版、互換版ではありません。

Liner が目指すのは、直接的なクローンではなく「Macらしい新解釈」です。

- 多数の楽曲を表形式で一括編集する
- macOS らしいサイドバー、ツールバー、インスペクタ、シート、メニューを活用する
- Finder からのドラッグ&ドロップを自然な読み込み導線にする
- タグ書き込みやファイル名変更の前に、安全なプレビューを表示する
- 将来的に Quick Look、Shortcuts、AppIntents などの macOS 機能を活用する

## MVP

最初のバージョンでは、MP3 ファイルと ID3v2 タグを優先します。

初期スコープ:

- フォルダ選択またはドラッグ&ドロップで MP3 ファイルを読み込む
- 1曲1行の編集可能なグリッドで表示する
- title、artist、album、album artist、track number、disc number、genre、year、comment などの主要タグを編集する
- 複数行への貼り付けに対応する
- トラック番号の連番を生成する
- 選択した複数ファイルへカバーアートを設定する
- タグをもとにしたテンプレートでファイル名を変更する
- 保存前に変更内容をプレビューする

FLAC / Vorbis Comment 対応は重要な将来機能ですが、まずは MP3 / ID3v2 の完成度を優先します。

## プロジェクト状態

現時点では企画・設計ドキュメントとリポジトリ運用の初期ファイルのみを配置しています。

Xcode プロジェクト、Swift Package、アプリ本体の実装はまだ作成していません。

## 対応予定

当面は GitHub Issues の milestone に沿って、以下の順で進めます。

- Project Foundation: 開発環境、技術選定、fixture 方針の決定
- App Skeleton: macOS アプリの骨格と初期 CI
- Metadata Model And MP3 Reading: MP3 / ID3v2 読み込み
- Spreadsheet Editing: 表形式の編集体験
- Write, Rename, Artwork: タグ書き込み、リネーム、カバーアート
- Quality, Safety, CI/CD: 安全性、署名、notarization、配布物作成
- First Public Preview: v0.1.0 preview

## 注意事項

- Liner はまだ利用可能なアプリではありません。
- 現時点では実際の音楽ファイルを読み書きする機能はありません。
- 将来的な初期版では、MP3 / ID3v2 を優先し、FLAC / Vorbis Comment は後続で検討します。
- ローカル音楽ファイルを変更するアプリになるため、保存前プレビュー、エラー表示、安全なリネームを重視して実装します。

## ドキュメント

- [プロダクトコンセプト](docs/product-concept.md)
- [実装ロードマップ](docs/implementation-roadmap.md)
- [公開・配布方針](docs/distribution-plan.md)
- [テスト用音源 fixture 方針](docs/test-fixtures.md)

## Localization

UI 文言は英語を source language とし、`Liner/Localizable.xcstrings` に `en` / `ja` の翻訳を追加します。SwiftUI では表示文言を `Text("Save Tags")`、`Label("Open", systemImage: "folder")`、`TableColumn("File")` のように文字列リテラルで渡し、変数経由で表示する UI 文言は `LocalizedStringKey` として保持してください。アプリ名など Info.plist 由来の文言は `Liner/InfoPlist.xcstrings` に追加します。

表示確認は Xcode の Scheme > Run > Options > App Language で English / Japanese を切り替えるか、CLI で `xcodebuild -scheme Liner -destination 'platform=macOS' build` を実行して localization resource がビルドに含まれることを確認します。

## ライセンス

MIT License
