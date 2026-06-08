import 'package:flutter_test/flutter_test.dart';
import 'package:rodmae_app/core/utils.dart';
import 'package:rodmae_app/models/finance_entry.dart';
import 'package:rodmae_app/models/surprise_note.dart';
import 'package:rodmae_app/models/love_trigger_event.dart';

void main() {
  group('RodMae App Unit Tests', () {
    test('Formatters money formatting verification', () {
      final formatted = Formatters.money(15000);
      expect(formatted, equals('PHP 15,000.00'));
    });

    test('Formatters compactMoney formatting verification', () {
      final formatted = Formatters.compactMoney(15000);
      expect(formatted, equals('PHP 15,000'));
    });

    test('FinanceEntry model parsing verification', () {
      final map = {
        'id': 'test-1',
        'title': 'Wedding Cake',
        'category': 'Food',
        'amount': 5500.50,
        'type': 'expense',
        'created_at': '2026-06-02T00:00:00Z',
        'created_by': 'Rodel',
      };

      final entry = FinanceEntry.fromMap(map);

      expect(entry.id, equals('test-1'));
      expect(entry.title, equals('Wedding Cake'));
      expect(entry.amount, equals(5500.50));
      expect(entry.type, equals(FinanceType.expense));
      expect(entry.createdBy, equals('Rodel'));
    });

    test('SurpriseNote model parsing verification', () {
      final map = {
        'id': 'note-1',
        'couple_id': 'couple-123',
        'sender': 'Mary Mae',
        'content': 'I love you so much!',
        'created_at': '2026-06-05T12:00:00Z',
      };

      final note = SurpriseNote.fromMap(map);

      expect(note.id, equals('note-1'));
      expect(note.coupleId, equals('couple-123'));
      expect(note.sender, equals('Mary Mae'));
      expect(note.content, equals('I love you so much!'));
    });

    test('LoveTriggerEvent model parsing verification', () {
      final map = {
        'id': 'trigger-1',
        'couple_id': 'couple-123',
        'sender': 'Rodel',
        'trigger_type': 'Flying Kiss',
        'created_at': '2026-06-05T12:05:00Z',
      };

      final trigger = LoveTriggerEvent.fromMap(map);

      expect(trigger.id, equals('trigger-1'));
      expect(trigger.coupleId, equals('couple-123'));
      expect(trigger.sender, equals('Rodel'));
      expect(trigger.triggerType, equals('Flying Kiss'));
    });
  });
}

