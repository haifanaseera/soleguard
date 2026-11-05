import 'dart:convert';

/// Rebuilds newline-terminated text lines from Bluetooth chunks.
///
/// The insole sends one JSON reading followed by "\n". Depending on the
/// packet size the phone agrees to, a reading arrives either in one piece
/// (MTU 247) or in 20-byte chunks. Feed every chunk to [add]; it returns the
/// complete lines found so far and keeps any unfinished part for next time.
class LineAssembler {
  /// A reading is about 205 bytes. Anything far longer is garbage.
  static const int maxLineBytes = 4096;

  final List<int> _buffer = [];

  /// True while the rest of an overlong line is being thrown away.
  bool _discarding = false;

  /// How many times the buffer was thrown away for growing too long.
  int overflowCount = 0;

  /// Bytes of an unfinished line that are waiting for the rest.
  int get pendingBytes => _buffer.length;

  List<String> add(List<int> bytes) {
    final lines = <String>[];
    for (final b in bytes) {
      if (b == 10) {
        // "\n": the line is complete.
        if (_discarding) {
          // End of an overlong line that was thrown away: start fresh.
          _discarding = false;
        } else if (_buffer.isNotEmpty) {
          lines.add(utf8.decode(_buffer, allowMalformed: true));
          _buffer.clear();
        }
      } else if (b != 13 && !_discarding) {
        // Ignore "\r", keep everything else.
        _buffer.add(b);
        if (_buffer.length > maxLineBytes) {
          // Far too long to be a reading: drop it, and drop the rest of this
          // line too, so the leftovers cannot spoil the next good reading.
          _buffer.clear();
          _discarding = true;
          overflowCount++;
        }
      }
    }
    return lines;
  }

  void clear() {
    _buffer.clear();
    _discarding = false;
  }
}
