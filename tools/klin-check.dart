// Reference checker run with Klin's own loader and checker (klin
// lib/project.dart, lib/checker.dart), in the format of
// tools/kliner-check: `ok`, or the first error as `L:C: message`. Run
// against a Klin checkout:
//   dart run --packages=PKG tools/klin-check.dart [--lib] [-I DIR]... FILE
// PKG maps `klin` to KLIN_SRC/lib (scripts/test.sh writes it). The file
// path is not printed: Klin names the wrong file for errors in imported
// modules (docs/04-checker.md), so only line, column and message are
// compared.
import 'dart:io';

import 'package:klin/checker.dart';
import 'package:klin/lexer.dart';
import 'package:klin/parser.dart';
import 'package:klin/preprocess.dart';
import 'package:klin/project.dart';

// `path:L:C: msg` -> `L:C: msg` (Kliner prints no path either).
String withoutPath(String s) {
  final m = RegExp(r'^.*?\.kl:(\d+:\d+: .*)$', dotAll: true).firstMatch(s);
  return m == null ? 'error: $s' : m.group(1)!;
}

void main(List<String> args) {
  final dirs = <String>[];
  var lib = false;
  String? entry;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-I' && i + 1 < args.length) {
      dirs.add(args[++i]);
    } else if (args[i] == '--lib') {
      lib = true;
    } else {
      entry = args[i];
    }
  }
  if (entry == null) {
    stderr.writeln('usage: klin-check [--lib] [-I DIR]... FILE');
    exit(2);
  }
  try {
    final program = loadProject(entry, klinPathDirs: dirs);
    Checker().check(program, requireMain: !lib);
  } on CheckError catch (e) {
    stdout.writeln('${e.pos.line}:${e.pos.col}: ${e.message}');
    exit(1);
  } on LexError catch (e) {
    stdout.writeln(withoutPath('$e'));
    exit(1);
  } on ParseError catch (e) {
    stdout.writeln(withoutPath('$e'));
    exit(1);
  } on PreprocessError catch (e) {
    stdout.writeln('error: $e');
    exit(1);
  } on FileSystemException catch (e) {
    stdout.writeln('error: ${e.message}: ${e.path}');
    exit(1);
  }
  stdout.writeln('ok');
}
