import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:radio8800_mobile/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  test('parses the packaged HamCQ repeater library', () {
    final raw = File('assets/data/hamcq-repeaters.json').readAsStringSync();
    final package = RepeaterLibraryPackage.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );

    expect(package.total, greaterThan(500));
    expect(package.repeaters.length, package.total);
    expect(package.regions, isNotEmpty);
    expect(package.repeaters.first.rxFreq, isNotEmpty);
  });

  test(
    'applies repeater tx frequency and explicit tones from library data',
    () {
      final store = MobileStore();
      final entry = RepeaterEntry(
        id: 'test',
        region: '7 区',
        province: '广东省',
        city: '深圳',
        name: '测试台',
        kind: '模拟',
        rxFreq: '439.46250',
        txFreq: '434.46250',
        offset: '-5.00000',
        toneText: 'T88.5 / TSQ88.5',
        txTone: '88.5',
        rxTone: '88.5',
      );

      store.applyRepeater(entry);

      final channel = store.data.channels[0][0];
      expect(channel.rxFreq, '439.46250');
      expect(channel.txFreq, '434.46250');
      expect(channel.rxTone, '88.5');
      expect(channel.txTone, '88.5');
      expect(channel.scanAdd, 1);
      expect(channel.busyLock, 1);
    },
  );

  test('deletes a selected backup snapshot', () {
    final store = MobileStore();
    store.backups.add(
      RadioSnapshot(
        id: 'a',
        title: '手动备份',
        createdAt: DateTime(2026, 6, 18),
        data: RadioAppData.defaults(),
      ),
    );

    store.deleteBackup('a');

    expect(store.backups, isEmpty);
    expect(store.notice?.text, contains('已删除备份'));
  });

  test('clears logs and leaves a clear marker', () {
    final store = MobileStore();
    store.logs.addAll(['old 1', 'old 2']);

    store.clearLogs();

    expect(store.logs.length, 1);
    expect(store.logs.first, contains('日志已清空'));
    expect(store.notice?.text, '日志已清空');
  });
}
