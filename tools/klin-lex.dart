// Reference token dump with Klin's own lexer (klin lib/lexer.dart), in
// the format of tools/kliner-lex (see its header). Run against a Klin
// checkout:
//   dart run --packages=PKG tools/klin-lex.dart FILE
// where PKG is a package_config.json mapping `klin` to KLIN_SRC/lib
// (scripts/test.sh writes it and compiles this file once).
import 'dart:convert';
import 'dart:io';

import 'package:klin/lexer.dart';
import 'package:klin/token.dart';

void put(StringBuffer o, List<int> bytes) {
  for (final c in bytes) {
    if (c == 0x5c) {
      o.write(r'\\');
    } else if (c >= 0x20 && c < 0x7f) {
      o.writeCharCode(c);
    } else {
      o.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
    }
  }
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: klin-lex FILE');
    exit(2);
  }
  final src = File(args[0]).readAsStringSync();
  final o = StringBuffer();
  List<Token> toks;
  try {
    toks = Lexer(src).tokenize();
  } on LexError catch (e) {
    stdout.write('${e.pos.line}:${e.pos.col}: ${e.message}\n');
    exit(1);
  }
  for (final t in toks) {
    o.write('${t.pos.line}:${t.pos.col} ${t.kind.name} ');
    var text = t.lexeme;
    if (t.kind == TokenKind.string) {
      // Klin marks an escaped `\$` as U+E000; Kliner keeps the bytes `\$`.
      text = text.replaceAll('\uE000', r'\$');
    }
    put(o, utf8.encode(text));
    o.write('\n');
  }
  stdout.write(o.toString());
}
