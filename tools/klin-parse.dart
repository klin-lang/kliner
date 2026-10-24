// Reference AST dump with Klin's own parser (klin lib/parser.dart), in
// the format of tools/kliner-parse (docs/03-ast-dump.md). Run against a
// Klin checkout:
//   dart run --packages=PKG tools/klin-parse.dart FILE
// PKG maps `klin` to KLIN_SRC/lib (scripts/test.sh writes it). The file
// is lexed and parsed as is: no `$fn` preprocessing (Kliner has none).
import 'dart:convert';
import 'dart:io';

import 'package:klin/ast.dart';
import 'package:klin/lexer.dart';
import 'package:klin/parser.dart';
import 'package:klin/token.dart';

final o = StringBuffer();
var depth = 0;

String q(String s) {
  final b = StringBuffer('"');
  for (final c in utf8.encode(s)) {
    if (c == 0x5c) {
      b.write(r'\\');
    } else if (c == 0x22) {
      b.write(r'\x22');
    } else if (c >= 0x20 && c < 0x7f) {
      b.writeCharCode(c);
    } else {
      b.write('\\x${c.toRadixString(16).padLeft(2, '0')}');
    }
  }
  b.write('"');
  return b.toString();
}

String opt(String? s) => s == null ? '-' : q(s);
String p(SourcePos pos) => '@${pos.line}:${pos.col}';
String b(bool v) => v ? '1' : '0';

void line(String tag, SourcePos? pos, [String attrs = '']) {
  o.write('  ' * depth);
  o.write(tag);
  if (pos != null) o.write(' ${p(pos)}');
  if (attrs.isNotEmpty) o.write(' $attrs');
  o.write('\n');
}

void kids(void Function() f) {
  depth++;
  f();
  depth--;
}

void attrs(List<Attr> xs) {
  for (final a in xs) {
    line('attr', a.pos, 'name=${q(a.name)} arg=${opt(a.arg)}');
  }
}

void unit(ModuleUnit u) {
  line('unit', null, 'module=${opt(u.declaredName)}');
  kids(() {
    for (final i in u.imports) {
      line('import', i.pos,
          'spec=${q(i.spec)} path=${b(i.isPath)} alias=${opt(i.alias)}');
    }
    for (final d in u.decls) {
      decl(d);
    }
  });
}

void decl(Object d) {
  switch (d) {
    case StructDecl s:
      line('struct', s.pos,
          'name=${q(s.name)} npos=${p(s.namePos)} pub=${b(s.isPub)}');
      kids(() {
        attrs(s.attrs);
        for (final f in s.fields) {
          line('field', f.pos, 'name=${q(f.name)} type=${q(f.typeName)}');
        }
      });
    case EnumDecl e:
      line('enum', e.pos,
          'name=${q(e.name)} npos=${p(e.namePos)} pub=${b(e.isPub)} base=${opt(e.baseTypeName)}');
      kids(() {
        attrs(e.attrs);
        for (final v in e.variants) {
          line('variant', v.pos, 'name=${q(v.name)}');
          if (v.value != null) kids(() => expr(v.value!));
        }
      });
    case ConstDecl c:
      line('const', c.pos,
          'name=${q(c.name)} npos=${p(c.namePos)} pub=${b(c.isPub)} type=${q(c.typeName)}');
      kids(() {
        attrs(c.attrs);
        expr(c.init);
      });
    case GlobalDecl g:
      line('global', g.pos,
          'name=${q(g.name)} npos=${p(g.namePos)} pub=${b(g.isPub)} mut=${b(g.isMut)} type=${q(g.typeName)}');
      kids(() {
        attrs(g.attrs);
        if (g.init != null) expr(g.init!);
      });
    case FuncDecl f:
      line('fn', f.pos,
          'name=${q(f.name)} npos=${p(f.namePos)} pub=${b(f.isPub)} async=${b(f.isAsync)} assoc=${opt(f.associatedType)} ret=${opt(f.returnTypeName)}');
      kids(() {
        attrs(f.attrs);
        final r = f.receiver;
        if (r != null) {
          line('recv', r.pos,
              'name=${q(r.name)} mut=${b(r.isMut)} type=${q(r.typeName)}');
        }
        for (final x in f.params) {
          line('param', x.pos, 'name=${q(x.name)} type=${q(x.typeName)}');
        }
        if (f.body != null) block(f.body!);
      });
  }
}

void block(Block bl) {
  line('block', bl.pos);
  kids(() {
    for (final s in bl.stmts) {
      stmt(s);
    }
  });
}

void stmt(Stmt s) {
  switch (s) {
    case AsmStmt a:
      line('asm', a.pos, 'code=${q(a.code)}');
    case LetStmt l:
      line('let', l.pos,
          'name=${q(l.name)} mut=${b(l.isMut)} short=${b(l.shortDecl)} type=${opt(l.typeName)}');
      if (l.init != null) kids(() => expr(l.init!));
    case LetDestructureStmt l:
      final fb = [
        for (var i = 0; i < l.fields.length; i++) '${l.fields[i]}:${l.binds[i]}'
      ].join(',');
      line('let-struct', l.pos, 'mut=${b(l.isMut)} binds=${q(fb)}');
      kids(() => expr(l.source));
    case LetArrayDestructureStmt l:
      line('let-array', l.pos,
          'mut=${b(l.isMut)} names=${q(l.names.map((n) => n ?? '_').join(','))}');
      kids(() => expr(l.source));
    case AssignStmt a:
      line('assign', a.pos, 'op=${opt(a.compoundOp)}');
      kids(() {
        expr(a.target);
        expr(a.value);
      });
    case MultiAssignStmt m:
      line('multi-assign', m.pos, 'n=${m.targets.length}');
      kids(() {
        m.targets.forEach(expr);
        m.values.forEach(expr);
      });
    case StructAssignStmt sa:
      line('struct-assign', sa.pos, 'fields=${q(sa.fields.join(','))}');
      kids(() {
        sa.targets.forEach(expr);
        expr(sa.source);
      });
    case CallStmt c:
      line('call', c.pos, 'mod=${opt(c.moduleName)} name=${q(c.callee)}');
      kids(() => c.args.forEach(expr));
    case MethodCallStmt m:
      expr(m.call);
    case AwaitStmt a:
      expr(a.expr);
    case IfStmt i:
      line('if', i.pos);
      kids(() {
        expr(i.cond);
        block(i.thenBlock);
        if (i.elseBranch != null) stmt(i.elseBranch!);
      });
    case WhileStmt w:
      line('while', w.pos);
      kids(() {
        expr(w.cond);
        block(w.body);
      });
    case ForRangeStmt f:
      line('for-range', f.pos, 'name=${q(f.name)}');
      kids(() {
        expr(f.start);
        expr(f.endExclusive);
        block(f.body);
      });
    case ForCStmt f:
      line('for-c', f.pos,
          'init=${opt(f.initName)} decl=${b(f.initDecl)} cond=${b(f.cond != null)} post=${opt(f.postName)} op=${opt(f.postCompoundOp)}');
      kids(() {
        if (f.initExpr != null) expr(f.initExpr!);
        if (f.cond != null) expr(f.cond!);
        if (f.postExpr != null) expr(f.postExpr!);
        block(f.body);
      });
    case ReturnStmt r:
      line('return', r.pos);
      if (r.value != null) kids(() => expr(r.value!));
    case BreakStmt br:
      line('break', br.pos);
    case ContinueStmt c:
      line('continue', c.pos);
    case DeferStmt d:
      line('defer', d.pos);
      kids(() => stmt(d.body));
    case BlockStmt bs:
      block(bs.block);
    case MatchStmt m:
      line('match', m.pos);
      kids(() {
        expr(m.subject);
        for (final a in m.arms) {
          line('arm', null, 'guard=${b(a.when != null)}');
          kids(() {
            pattern(a.pattern);
            if (a.when != null) expr(a.when!);
            block(a.body);
          });
        }
      });
  }
}

void pattern(MatchPattern pt) {
  switch (pt) {
    case LitPattern l:
      line('pat-lit', l.pos);
      kids(() => l.values.forEach(expr));
    case RangePattern r:
      line('pat-range', r.pos);
      kids(() {
        expr(r.start);
        expr(r.endInclusive);
      });
    case RelPattern r:
      line('pat-rel', r.pos, 'op=${q(r.op)}');
      kids(() => expr(r.rhs));
    case WildPattern w:
      line('pat-wild', w.pos);
    case ElsePattern e:
      line('pat-else', e.pos);
  }
}

void expr(Expr e) {
  switch (e) {
    case IntLit x:
      line('int', x.pos, 'v=${q(x.lexeme)}');
    case FloatLit x:
      line('float', x.pos, 'v=${q(x.lexeme)}');
    case BoolLit x:
      line('bool', x.pos, 'v=${x.value}');
    case StringLit x:
      line('str', x.pos, 'v=${q(x.value)}');
    case ByteStringLit x:
      line('bytes', x.pos, 'v=${q(x.value)}');
    case InterpolatedStringExpr x:
      line('interp', x.pos);
    case NameExpr x:
      line('name', x.pos, 'v=${q(x.name)}');
    case FieldExpr x:
      line('get', x.pos, 'name=${q(x.name)}');
      kids(() => expr(x.object));
    case MethodCallExpr x:
      line('mcall', x.pos, 'name=${q(x.name)}');
      kids(() {
        expr(x.receiver);
        x.args.forEach(expr);
      });
    case StructLitExpr x:
      final named = x.namedFields != null;
      final names = named ? x.namedFields!.keys.join(',') : '';
      line('struct-lit', x.pos,
          'mod=${opt(x.moduleName)} type=${q(x.typeName)} named=${b(named)} fields=${q(names)}');
      kids(() {
        if (named) {
          x.namedFields!.values.forEach(expr);
        } else {
          x.positionalFields!.forEach(expr);
        }
      });
    case CallExpr x:
      line('call', x.pos, 'mod=${opt(x.moduleName)} name=${q(x.callee)}');
      kids(() => x.args.forEach(expr));
    case UnaryExpr x:
      line('unary', x.pos, 'op=${q(x.op)}');
      kids(() => expr(x.operand));
    case IndexExpr x:
      line('index', x.pos);
      kids(() {
        expr(x.object);
        expr(x.index);
      });
    case SliceFromExpr x:
      line('slice', x.pos,
          'start=${b(x.start != null)} end=${b(x.end != null)}');
      kids(() {
        expr(x.array);
        if (x.start != null) expr(x.start!);
        if (x.end != null) expr(x.end!);
      });
    case ArrayLitExpr x:
      line('array', x.pos);
      kids(() => x.elements.forEach(expr));
    case CastExpr x:
      line('cast', x.pos, 'type=${q(x.typeName)}');
      kids(() => expr(x.expr));
    case BinaryExpr x:
      line('binary', x.pos, 'op=${q(x.op)}');
      kids(() {
        expr(x.left);
        expr(x.right);
      });
    case GroupExpr x:
      line('group', x.pos);
      kids(() => expr(x.inner));
    case ErrorExpr x:
      line('error', x.pos);
      kids(() => expr(x.code));
    case PropagateExpr x:
      line('propagate', x.pos);
      kids(() => expr(x.result));
    case AwaitExpr x:
      line('await', x.pos);
      kids(() => expr(x.operand));
    case OrExpr x:
      line('or', x.pos);
      kids(() {
        expr(x.result);
        line('or-block', x.fallback.pos, 'n=${x.fallback.stmts.length}');
        kids(() {
          x.fallback.stmts.forEach(stmt);
          final v = x.fallback.value;
          if (v != null) expr(v);
        });
      });
    case MatchExpr x:
      line('match-expr', x.pos);
      kids(() {
        expr(x.subject);
        for (final a in x.arms) {
          line('arm', null, 'guard=${b(a.when != null)}');
          kids(() {
            pattern(a.pattern);
            if (a.when != null) expr(a.when!);
            expr(a.body);
          });
        }
      });
    case PickExpr x:
      line('pick', x.pos);
      kids(() {
        expr(x.cond);
        expr(x.thenExpr);
        expr(x.elseExpr);
      });
  }
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: klin-parse FILE');
    exit(2);
  }
  final src = File(args[0]).readAsStringSync();
  try {
    unit(Parser(Lexer(src).tokenize()).parseUnit());
  } on LexError catch (e) {
    stdout.write('${e.pos.line}:${e.pos.col}: ${e.message}\n');
    exit(1);
  } on ParseError catch (e) {
    stdout.write('${e.pos.line}:${e.pos.col}: ${e.message}\n');
    exit(1);
  }
  stdout.write(o.toString());
}
