import 'package:flutter_test/flutter_test.dart';
import 'package:radio8800_mobile/main.dart';

void main() {
  test('starts with an empty codeplug by default', () {
    final data = RadioAppData.defaults();

    expect(data.visibleChannelCount, 0);
    expect(data.hasBackupContent, isFalse);
  });

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

  test('fills empty bank name slots with FF when no raw block exists', () {
    final data = RadioAppData.defaults();
    data.bankNames[1] = '';

    final block = ShxCodec.bluetoothWriteBlocks(
      data,
    ).firstWhere((item) => item.address == ShxCodec.bankNameAAddress);
    final emptySlot = block.payload.sublist(16, 28);

    expect(emptySlot.every((byte) => byte == 0xff), isTrue);
  });

  test('encodes and decodes DCS tones like the web codec', () {
    final data = RadioAppData.defaults();
    data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      rxTone: 'D023N',
      txTone: 'D754I',
      visible: true,
    );

    final block = ShxCodec.bluetoothWriteBlocks(
      data,
    ).firstWhere((item) => item.address == 0x0000);
    expect(block.payload[8], 1);
    expect(block.payload[9], 0);
    expect(block.payload[10], ToneLibrary.dcs.indexOf('D754I') + 1);
    expect(block.payload[11], 0);

    final decoded = RadioAppData.defaults();
    ShxCodec.applyBlock(decoded, block.address, block.payload);
    expect(decoded.channels[0][0].rxTone, 'D023N');
    expect(decoded.channels[0][0].txTone, 'D754I');
  });

  test('backup signatures ignore timestamp changes', () {
    final data = RadioAppData.defaults();
    expect(data.hasBackupContent, isFalse);

    data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      visible: true,
    );
    final before = data.backupSignature;
    data.updatedAt = data.updatedAt.add(const Duration(minutes: 5));

    expect(data.hasBackupContent, isTrue);
    expect(data.backupSignature, before);
  });

  test('copies and pastes channels while keeping target id', () {
    final store = MobileStore();
    store.data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '439.46250',
      txFreq: '434.46250',
      name: '梧桐山',
      visible: true,
    );

    store.selectChannel(1);
    store.copyCurrentChannel();
    store.selectChannel(2);
    store.pasteToCurrentChannel();

    expect(store.data.channels[0][1].id, 2);
    expect(store.data.channels[0][1].rxFreq, '439.46250');
    expect(store.data.channels[0][1].name, '梧桐山');
  });

  test('deletes a channel and shifts following channels up', () {
    final store = MobileStore();
    store.data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '430.00000',
      visible: true,
    );
    store.data.channels[0][1] = Channel(
      id: 2,
      rxFreq: '431.00000',
      visible: true,
    );
    store.data.channels[0][2] = Channel(
      id: 3,
      rxFreq: '432.00000',
      visible: true,
    );

    store.selectChannel(2);
    store.deleteCurrentChannelAndShift();

    expect(store.data.channels[0][0].id, 1);
    expect(store.data.channels[0][1].id, 2);
    expect(store.data.channels[0][1].rxFreq, '432.00000');
    expect(store.data.channels[0].last.id, 64);
    expect(store.data.channels[0].last.visible, isFalse);
  });

  test('compacts active channels to the front of the selected bank', () {
    final store = MobileStore();
    store.data.channels[0][0] = Channel(
      id: 1,
      rxFreq: '430.00000',
      visible: true,
    );
    store.data.channels[0][3] = Channel(
      id: 4,
      rxFreq: '433.00000',
      visible: true,
    );
    store.data.channels[0][7] = Channel(
      id: 8,
      rxFreq: '437.00000',
      visible: true,
    );

    store.compactCurrentBank();

    expect(store.data.channels[0][0].id, 1);
    expect(store.data.channels[0][0].rxFreq, '430.00000');
    expect(store.data.channels[0][1].id, 2);
    expect(store.data.channels[0][1].rxFreq, '433.00000');
    expect(store.data.channels[0][2].id, 3);
    expect(store.data.channels[0][2].rxFreq, '437.00000');
    expect(store.data.channels[0][3].visible, isFalse);
  });
}
