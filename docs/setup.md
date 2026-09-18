# AIメモリーいらんかえ～ 簡単セットアップガイド

## 1. マーケットプレース

配布サイト（この URL を起点にインストールします）:

```text
https://storage.googleapis.com/hackathon-ai-memory-plugin
```

## 2. プラグインを入れる

### Claude Code

```text
/plugin marketplace add https://storage.googleapis.com/hackathon-ai-memory-plugin/marketplace.json
/plugin install ai-memory@hackathon-ai-memory
```

### Cursor

Cursor の Team Marketplace は現状 Git リポジトリ前提のため、GCS 上の zip をローカルに入れて使います。

```bash
curl -fsSL "https://storage.googleapis.com/hackathon-ai-memory-plugin/plugins/ai-memory.zip" -o ai-memory.zip
mkdir -p ~/.cursor/plugins/local
unzip -o ai-memory.zip -d ~/.cursor/plugins/local
```

Cursor をリロード（Developer: Reload Window）してください。

### Gemini CLI

```bash
curl -fsSL "https://storage.googleapis.com/hackathon-ai-memory-plugin/plugins/ai-memory.zip" -o ai-memory.zip
unzip -o ai-memory.zip -d /tmp
gemini extensions install /tmp/ai-memory
```

## 3. API キーを設定する

発行された API キーを `AI_MEMORY_API_KEY` として設定します。

- Claude Code: プラグインの user config
- Cursor: Plugins → Configure（variables）
- Gemini CLI: 拡張機能の設定（install 時のプロンプト）

## 4. 推奨スキル（elasticsearch-esql）

本プラグインの利用時は、[elastic/agent-skills](https://github.com/elastic/agent-skills) の **elasticsearch-esql** スキルのインストールを推奨します。ES|QL での検索・集計がしやすくなります。

```bash
npx skills add elastic/agent-skills --skill elasticsearch-esql
```

Claude Code の場合は、マーケットプレース追加後に Elasticsearch プラグインを入れる方法でも構いません（`elasticsearch-esql` を含みます）:

```bash
claude plugin marketplace add https://github.com/elastic/agent-skills
claude plugin install elastic-elasticsearch@elastic-agent-skills
```

## 5. 使ってみる

エージェントに自然言語で依頼します。

- 「〇〇を覚えて」→ 記憶として保存
- 「〇〇って何だっけ？」→ 記憶を検索して回答

## 注意

ハッカソン向けの最低限のセキュリティです。個人情報や機密情報は絶対に登録しないでください。
