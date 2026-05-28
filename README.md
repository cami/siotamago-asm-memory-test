# nrf52840-memory-test

nRF52840 のメモリテスト用リポジトリです。
まずは「RAM 全域テスト」を実装しています。

この構成は https://github.com/cami/siotamago-asm-example-led.git を参考に、
PlatformIO が配布する GNU Arm ツールチェーンを直接利用する最小構成にしています。

## できること（現時点）

- アセンブリ: `src/main.S`
- リンク: `linker.ld`
- 生成物: `build/main.elf`, `build/main.hex`
- テスト対象: RAM 全域 (`0x20000000` - `0x2003FFFF`)
- 結果表示:
  - 遅い点滅: PASS
  - 速い点滅: FAIL

## 注意

- RAM テストは破壊的です。RAM 内容は全て上書きされます。
- 実行中は割り込みを禁止します。
- テストループは無限ループです。

## 前提

- Linux
- PlatformIO Core (`pio` コマンド)
- 書き込み時のみ J-Link または nrfjprog

## 1. ツールチェーンの取得

```bash
pio pkg install --global --tool toolchain-gccarmnoneeabi
```

## 2. ビルド

```bash
./scripts/build.sh
```

成功すると `build/main.hex` が生成されます。

## 3. 書き込み

### J-Link で書き込む

```bash
pio pkg install --global --tool tool-jlink
./scripts/flash_jlink.sh
```

### nrfjprog で書き込む

```bash
./scripts/flash_nrfjprog.sh
```

## 所要時間の概算

- ビルド: 1 秒未満（このPCでの実測は 0 秒表示）
- J-Link 書き込み: 約 1 秒（このPCでの実測）
- RAM 全域テスト本体（起動後の走査）: 約 0.1 - 0.5 秒
- 目安の合計（build + flash + 実行開始）: 約 1 - 2 秒

補足:

- 参照リポジトリ `asmtest00` と同一の `scripts/build.sh` / `scripts/flash_jlink.sh` を使用しています。
- RAM テストは完了後に無限ループへ入り、LED 点滅で PASS/FAIL を表示し続けます。
- `nrfjprog` はこの環境では未導入でした（J-Link は `JLinkExe` で動作確認済み）。

## 次の実装予定

- フラッシュ全域テスト
- RAM/フラッシュ個別テストの結果アドレス表示（必要なら UART/SWO 対応）
