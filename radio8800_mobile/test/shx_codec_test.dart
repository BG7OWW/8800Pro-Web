import 'package:flutter_test/flutter_test.dart';
import 'package:radio8800_mobile/main.dart';

void main() {
  test('preserves Chinese channel and bank names in radio text fields', () {
    final data = RadioAppData.defaults();
    data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      name: '梧桐山',
      visible: true,
    );
    data.bankNames[0] = '区域一ABC';

    final blocks = ShxCodec.bluetoothWriteBlocks(data);
    final channelBlock = blocks.firstWhere((block) => block.address == 0x0000);
    final bankNameBlock = blocks.firstWhere(
      (block) => block.address == ShxCodec.bankNameAAddress,
    );

    final decoded = RadioAppData.defaults();
    ShxCodec.applyBlock(decoded, channelBlock.address, channelBlock.payload);
    ShxCodec.applyBlock(decoded, bankNameBlock.address, bankNameBlock.payload);

    expect(decoded.channels[0][0].name, '梧桐山');
    expect(decoded.bankNames[0], '区域一ABC');
  });
}
