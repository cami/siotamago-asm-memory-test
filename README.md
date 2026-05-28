# nrf52840-memory-test

nRF52840 向けのベアメタルメモリテストです。  
RAM テストと Flash テストを、単一のアセンブリ実装で実行します。

この構成は https://github.com/cami/siotamago-asm-example-led.git を参考に、
PlatformIO が配布する GNU Arm ツールチェーンを直接利用する最小構成にしています。

## 現在の実装

- 実装本体: src/main.S
- リンカ: linker.ld
- 生成物: build/main.elf, build/main.hex

### テスト対象

- RAM: 0x20000000 - 0x2003CFFF
  - 注意: RAM 上位領域 (ベクタ/ステージ配置領域) を壊さないため、RAM 全域ではなく上記範囲をテスト
- Flash: 0x00000000 - 0x000FFFFF (全域)
  - ページサイズ: 4 KiB

### 実行アーキテクチャ

- 起動後に RAM テストを実行
- Flash テストコード本体を RAM (0x2003E000) にコピーして実行
- RAM 上にベクタテーブルを構築し、VTOR を RAM へ切り替え
- Flash テストはページ単位で erase -> verify erased -> program -> verify pattern を実行
- NVMC の CONFIG 切り替え後は DSB/ISB を実行してモード反映を同期
- Flash ベリファイの整合性を優先し、テスト開始時に NVMC I-Cache を無効化

### 保護領域の扱い

- 現在のファームでは ACL 判定は一時的に無効化している
   - `flash_page_acl_mode` は常に `0` を返し、全ページを通常ページとして処理
   - そのため ACL の write/read 制限に応じた分岐は行わない
- 今後、完走安定性を維持したまま ACL 判定ロジックを段階的に再有効化する予定

### 監視・可視化

- WDT 給餌を長時間ループ中に実行
- RTT バッファを RAM に作成
  - 制御ブロック: 0x2003B000
  - 出力バッファ: 0x2003B100 (256 bytes)
   - 代表ログ: START, ERR=XXXXXXXX PAGE=XXXXXXXX

### LED 意味付け (設計意図)

- 緑のLED (論理名: LED_BLUE): 進捗表示/正常完了表示
- 赤のLED (論理名: LED_RED): エラー表示
- 起動時: 緑のLEDを短時間点灯 -> 消灯、続けて赤のLEDを短時間点灯 -> 消灯
- fault_handler: 赤のLED点滅 (緑のLED消灯) で区別

注意: ボード側 LED 配線と active-low 特性の差で、物理表示が意図とずれる可能性があります。下記の未解決課題を参照してください。

## 使い方

### 1. ツールチェーン取得

```bash
pio pkg install --global --tool toolchain-gccarmnoneeabi
```

### 2. ビルド

```bash
./scripts/build.sh
```

### 3. 書き込み (J-Link)

```bash
pio pkg install --global --tool tool-jlink
./scripts/flash_jlink.sh
```

### 4. フラッシュ時刻の記録と経過確認

```bash
./scripts/flash_and_record.sh
./scripts/check_test_elapsed.sh
```

- `flash_and_record.sh`
   - `build/flash_history.log` に開始/終了時刻を追記
   - `build/last_flash_epoch.txt` に直近フラッシュ開始時刻を保存
- `check_test_elapsed.sh`
   - 直近フラッシュからの経過時間を表示
   - J-Link で現在 PC と RAM 状態フラグ (`0x2003B204`) を取得し、`test_running` / `pass_loop` / `fail_loop` を判定
   - RAM カーソル (`0x2003B200`) から `page_addr` / 進捗率 / 推定残り時間を表示
   - `test_running` が 15 分超なら注意メッセージを表示

### 5. 完了までの自動監視

```bash
./scripts/monitor_test_until_done.sh
```

- 5 秒間隔で `check_test_elapsed.sh` を実行
- `pass_loop` 到達で終了 (exit code 0)
- `fail_loop` 到達で終了 (exit code 2)
- 既定 30 分でタイムアウト (exit code 3)

オプション例:

```bash
./scripts/monitor_test_until_done.sh --interval 3 --max-seconds 1200
./scripts/monitor_test_until_done.sh --once
```

## 実行時間の目安

- ビルド: 1 秒未満
- J-Link 書き込み: 約 1 秒
- RAM テスト: 1 秒未満
- Flash テスト: 実測で約 36 秒
- フラッシュ後のテスト完了まで: 実測で 1 分未満

## 注意事項

- RAM テスト/Flash テストは破壊的です。
- Flash テストで既存ファームウェアは上書きされます。
- 割り込みは禁止して実行します。
- テスト中は無限ループで状態表示を継続します。

## 現在残っている課題

1. LED 表示の最終同定
   - 設計意図は 緑のLED(LED_BLUE)=進捗/正常、赤のLED(LED_RED)=エラー
   - ただし実機観測とのズレが断続的に発生しており、配線/極性/経路別制御の最終同定が未完了
2. RTT ホスト取得経路の整備
   - ファーム側 RTT 出力は有効
   - ただしこの環境では RTT サーバ系ツールが不足しており、現在は RAM 直接ダンプで確認している
3. ACL 判定ロジックの再有効化
   - 現在は ACL を無効化して完走優先で運用中
   - ACL の read-only / locked 分岐を再導入し、再度完走性を検証する
4. エラー再現時の詳細ダンプ強化
   - ERR/PAGE は出力済み
   - 必要に応じて expected/actual 値や失敗ワード index の追加出力を検討
