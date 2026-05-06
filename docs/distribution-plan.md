# 公開・配布方針

## 概要

Liner は macOS 専用アプリとして、まず GitHub を中心に公開します。

初期段階では App Store 公開を急がず、GitHub Releases で配布しながら、Developer ID 署名と notarization によってユーザーが安心して起動できる状態を目指します。

## 基本方針

公開・配布は以下の順番で進めます。

1. GitHub でソースコードを公開する
2. GitHub Releases で notarized DMG または ZIP を配布する
3. 自前 Homebrew Tap で `brew install --cask liner` に対応する
4. 安定性と認知が出てから公式 Homebrew Cask を検討する
5. Mac App Store は後で判断する

この順番にする理由は、Liner がローカル音楽ファイルのタグ書き込みやファイル名変更を扱うアプリだからです。まずはファイル操作系アプリとしての安全性、権限設計、保存前プレビュー、エラー処理を固めます。

## GitHub Releases

最初の一般配布は GitHub Releases を想定します。

配布物:

- `Liner.dmg`
- または `Liner.zip`
- リリースノート
- 対応 macOS バージョン
- 既知の制限

GitHub Releases は、初期ユーザーや開発者にとって入手しやすく、ソースコード、issue、release note を同じ場所に置ける点が扱いやすいです。

## 署名と Notarization

他の人に使ってもらう段階では、Developer ID 署名と notarization を前提にします。

目標:

- Gatekeeper 有効環境で自然に起動できる
- ユーザーが「開発元を確認できないため開けません」という強い警告に遭遇しない
- 配布物が改ざんされていないことを確認できる

このため、初期の公開準備では Apple Developer Program への登録、Developer ID 証明書、notarytool を使った notarization、配布物への stapling を調査します。

## 自前 Homebrew Tap

GitHub Releases で配布できる状態になったら、自前 Homebrew Tap を用意します。

想定コマンド:

```sh
brew tap <owner>/liner
brew install --cask liner
```

自前 tap は、公式 Homebrew Cask に入る前でもすぐに提供できます。開発者やCLIに慣れたMacユーザーにとって導入しやすい配布経路になります。

## 公式 Homebrew Cask

アプリが安定し、一定の認知や利用実績が出てから公式 Homebrew Cask への追加を検討します。

検討前に満たしたい条件:

- 安定版リリースが存在する
- GitHub Releases などで継続的に配布されている
- notarized app として Gatekeeper 環境で起動できる
- README や公式ページに十分な説明がある
- 更新が継続される見込みがある

Homebrew Cask はアプリ発見のための場所ではないため、最初から公式登録を目標にしすぎず、まずは自前配布を安定させます。

## Mac App Store

Mac App Store は、Liner の初期公開手段にはしません。

将来的に検討する理由:

- 一般ユーザーにとって安心感がある
- 自動更新が標準で提供される
- Apple の配布基盤を使える

慎重に判断する理由:

- App Review への対応が必要
- sandbox やファイルアクセス権限の設計が重要になる
- ローカルファイルのタグ書き込み、ファイル名変更、フォルダ単位の操作との相性を検証する必要がある

まずは App Store 外配布で Liner の実用性を固め、sandbox 前提でも自然に使える見通しが立ってから判断します。

## 将来の自動アップデート

GitHub Releases 配布が安定した後、アプリ内自動アップデートの導入を検討します。

候補:

- Sparkle
- 独自の更新確認
- Homebrew 経由の更新に任せる

初期段階では、リリースごとの手動ダウンロードと Homebrew Tap 更新で十分とします。

## 初期リリース前チェックリスト

- GitHub リポジトリを公開できる状態にする
- README にアプリ概要、影響を受けた思想、独立性、対応形式、注意事項を書く
- ライセンスを決める
- 対応 macOS バージョンを明記する
- Developer ID 署名と notarization の手順を確立する
- DMG または ZIP を作成する
- Gatekeeper 有効環境で初回起動を確認する
- リリースノートを作成する
- 自前 Homebrew Tap の cask を用意する
