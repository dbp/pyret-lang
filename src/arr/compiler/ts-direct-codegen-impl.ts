import * as J from 'estree';
import type * as Escodegen from 'escodegen';
import type * as Path from 'path';
import type * as A from './ts-ast';
import type * as CS from './ts-compile-structs';
import { objectExpression } from '@babel/types';

({ 
  requires: [],
  nativeRequires: ["escodegen", "path"],
  provides: {
    values: {
      "compile-program": "tany"
    }
  },
  theModule: function(runtime, _, ___, escodegen : (typeof Escodegen), P : (typeof Path)) {
    // Pretty-print JS asts
    // Return a PyretObject
    // Type enough AST to get to s-num

    type Variant<T, V> = T & { $name: V };

    class ExhaustiveSwitchError extends Error {
      constructor(v: never, message?: string) {
        super(`Switch is not exhaustive on \`${JSON.stringify(v)}\`: ${message}`);
      }
    }
    class InternalCompilerError extends Error {
      constructor(message: string) {
        super(`Internal compile error (compiler bug/broken invariant): ${message}`);
      }
    }
    class TODOError extends Error {
      constructor(message: string) {
        super(`Incomplete feature in compiler: ${message}`);
      }
    }

    type PyretObject = {
      dict: any
    };

    function ExpressionStatement(e : J.Expression) : J.Statement {
      return { type: "ExpressionStatement", expression: e };
    }
    function CallExpression(callee : J.Expression, args: Array<J.Expression>) : J.Expression {
      return {
        type: "CallExpression",
        callee: callee,
        arguments: args,
        optional: false
      };
    }
    function MethodCallExpression(obj : J.Expression, field : string, args: Array<J.Expression>) : J.Expression {
      return {
        type: "CallExpression",
        callee: DotExpression(obj, field),
        arguments: args,
        optional: false
      };
    }
    function DotExpression(object : J.Expression, property : string) : J.MemberExpression {
      return {
        type: "MemberExpression",
        object: object,
        property: Literal(property),
        computed: true,
        optional: false
      }
    }
    function BracketExpression(object : J.Expression, property : J.Expression) : J.MemberExpression {
      return {
        type: "MemberExpression",
        object: object,
        property: property,
        computed: true,
        optional: false
      }
    }
    function Literal(a : any) : J.Expression {
      if(a === undefined) { throw new InternalCompilerError("undefined given to Literal"); }
      return {
        type: "Literal",
        value: a
      };
    }
    function Identifier(id : A.Name) : J.Identifier {
      return {
        type: "Identifier",
        name: nameToSourceString(id)
      };
    }
    function ReturnStatement(e : J.Expression) : J.Statement {
      return {
        type: "ReturnStatement",
        argument: e
      }
    }
    function Var(id : A.Name, expr : J.Expression) : J.Declaration {
      return {
        type: "VariableDeclaration",
        kind: "var",
        declarations: [ { type: "VariableDeclarator", id: Identifier(id), init: expr }]
      };
    }
    function FunctionExpression(id : A.Name, args : Array<A.Name>, body : J.BlockStatement) : J.Expression {
      return {
        type: "FunctionExpression",
        id: Identifier(id),
        params: args.map(Identifier),
        body
      };
    }
    function AssignmentExpression(lhs : J.MemberExpression | J.Identifier, rhs : J.Expression) : J.Expression {
      return {
        type: "AssignmentExpression",
        operator: "=",
        left: lhs,
        right: rhs
      }
    }
    function BinaryExpression(op : J.BinaryOperator, left : J.Expression, right : J.Expression) : J.Expression {
      return {
        type: "BinaryExpression",
        operator: op,
        left: left,
        right: right
      };
    }
    function ConditionalExpression(cond : J.Expression, thn : J.Expression, els : J.Expression) : J.Expression {
      return {
        type: "ConditionalExpression",
        test: cond,
        consequent: thn,
        alternate: els
      };
    }
    function ArrayExpression(values : Array<J.Expression>) : J.Expression {
      return {
        type: "ArrayExpression",
        elements: values
      }
    }
    function ObjectExpression(properties : Array<J.Property>) : J.Expression {
      return {
        type: "ObjectExpression",
        properties: properties
      };
    }
    function Getter(name : string, value : J.Expression) : J.Property {
      return {
        type: "Property",
        kind: "get",
        key: Literal(name),
        value: value,
        method: false,
        shorthand: false,
        computed: true
      };
    }
    function Property(name : string, value : J.Expression) : J.Property {
      return {
        type: "Property",
        kind: "init",
        key: Literal(name),
        value: value,
        method: false,
        shorthand: false,
        computed: true
      };
    }
    function Program(body : Array<J.Statement>) : J.Program {
      return {
        sourceType: "module",
        type: "Program",
        body: body
      };
    }

    function UnaryExpression(operator: J.UnaryOperator, argument : J.Expression) : J.Expression {
      return {
        type: "UnaryExpression",
        operator,
        argument,
        prefix: true,
      };
    }

    function LogicalExpression(operator : J.LogicalOperator, left: J.Expression, right: J.Expression) : J.Expression {
      return {
        type: "LogicalExpression",
        left,
        right,
        operator,
      };
    }

    function BlockStatement(stmts : J.Statement[]) : J.BlockStatement {
      return {
        type: 'BlockStatement',
        body: stmts,
      }
    }

    function IfStatement(test: J.Expression, thn: J.Statement, els: J.Statement): J.IfStatement {
      return {
        type: 'IfStatement',
        test,
        consequent: thn,
        alternate: els,
      };
    }


    function MakeName(start : number) {
      var count = start;
      function atom(base : string) : A.Name {
        count = count + 1;
        return { $name: "s-atom", dict: { base: base, serial: count }};
      }
      return {
        reset: () => count = start,
        sUnderscore: (l : A.Srcloc) : A.Name => ({ $name: "s-underscore", dict: { l }}),
        sName: (s : string, l : A.Srcloc) : A.Name => ({ $name: "s-name", dict: { s, l }}),
        sGlobal: (s : string) : A.Name => ({ $name: "s-global", dict: { s }}),
        sModuleGlobal: (s : string) : A.Name => ({ $name: "s-module-global", dict: { s }}),
        sTypeGlobal: (s : string) : A.Name => ({ $name: "s-type-global", dict: { s }}),
        makeAtom : atom,
        isSUnderscore: v => v.$name === "s-underscore",
        isSName: v => v.$name === "s-name",
        isSGlobal: v => v.$name === "s-global",
        isSModuleGlobal: v => v.$name === "s-module-global",
        isSAtom: v => v.$name === "s-atom",
      };
    }

    // NOTE(joe): Function version of to-sourcestring() method on Name in ast.arr
    function nameToSourceString(name : A.Name) : string {
      switch(name.$name) {
        case "s-underscore": return "_";
        case "s-name": return name.dict.s;
        case "s-global": return name.dict.s;
        case "s-module-global": return "$module$" + name.dict.s;
        case "s-type-global": return "$type$" + name.dict.s;
        case "s-atom": return name.dict.base + String(name.dict.serial);
      }
    }

    // NOTE(joe): Function version of toname() method on Name in ast.arr
    function nameToName(name : A.Name) : string {
      switch(name.$name) {
        case "s-underscore": return "_";
        case "s-atom": return name.dict.base;
        default: return name.dict.s;
      }
    }

    function nameToKey(name : A.Name) : string {
      switch(name.$name) {
        case "s-underscore": return "underscore#";
        case "s-name": return "name#" + name.dict.s;
        case "s-global": return "global#" + name.dict.s;
        case "s-module-global": return "mglobal#" + name.dict.s;
        case "s-type-global": return "tglobal#" + name.dict.s;
        case "s-atom": return "atom#" + name.dict.base + "#" + String(name.dict.serial);
      }
    }

    const dummyLoc : A.Srcloc = {
      $name: "builtin",
      dict: { 'module-name': "dummy location" }
    };

    const jsnames = MakeName(0);
    const jsIds = new Map<string, A.Name>();
    const effectiveIds = new Map<string, boolean>();

    function freshId(id : A.Name) : A.Name {
      let n;
      do {
        const baseName = id.$name === "s-type-global" ? nameToSourceString(id) : nameToName(id);
        const noHyphens = baseName.replace("-", "$");
        n = jsnames.makeAtom(noHyphens);
      } while(effectiveIds.has(nameToSourceString(n)));
      effectiveIds.set(nameToSourceString(n), true);
      return n;
    }
    function jsIdOf(id : A.Name) : A.Name {
      const s = nameToKey(id);
      if (jsIds.has(s)) { return jsIds.get(s); }
      else {
        const safeId = freshId(id);
        jsIds.set(s, safeId);
        return safeId;
      }
    }
    function constId(name : string) : A.Name {
      return {
        $name: "s-name",
        dict: {
          l: dummyLoc,
          s: name
        }
      }
    }
    function compilerName(id: string) : A.Name {
      return constId("$" + id)
    }

    const RUNTIME = constId("_runtime");
    const NUMBER_ERR_CALLBACKS = "$errCallbacks"
    const EQUAL_ALWAYS = "equal-always"
    const IDENTICAL = "identical"

    function compressRuntimeName(name : string) { return name; }
    
    function rtField(name : string) {
      return DotExpression(Identifier(RUNTIME), name);
    }

    function rtMethod(name : string, args : Array<J.Expression>) {
      return CallExpression(DotExpression(Identifier(RUNTIME), compressRuntimeName(name)), args);
    }

    function compileList(context, exprs: A.List<A.Expr>) : [ Array<J.Expression>, Array<J.Statement> ] {
      if(exprs.$name === 'empty') { return [[], []]; }
      else {
        const [ firstAns, startStmts ] = compileExpr(context, exprs.dict.first);
        const [ restAns, restStmts ] = compileList(context, exprs.dict.rest);
        return [ [firstAns, ...restAns], [...startStmts, ...restStmts] ];
      }
    }

    function compileSeq(context, exprs : A.List<A.Expr>) : [J.Expression, Array<J.Statement>] {
      if(exprs.$name === 'empty') { throw new InternalCompilerError("Empty block reached codegen"); }
      let ans, stmts = [];
      let cur: A.List<A.Expr> = exprs;
      while (cur.$name === 'link') {
        const [first, firstStmts] = compileExpr(context, cur.dict.first);
        ans = first;
        stmts.push(...firstStmts);
        cur = cur.dict.rest;
      }
      return [ans, stmts]
    }

    function listToArray<T>(l : A.List<T>) : Array<T> {
      return runtime.ffi.toArray(l);
    }

    function compileMethodDefinition(context, method : Variant<A.Member, "s-method-field">) {
      const args = method.dict.args as Variant<A.List<Variant<A.Bind, "s-bind">>, "link">
      const self = jsIdOf(args.dict.first.dict.id);
      const lamProps = method.dict;
      // This removes the `self` argument from the args list for use in the curried method
      // From well-formed, we know methods have at least one argument
      lamProps.args = args.dict.rest;
      const [curriedFunction, _] = compileExpr(context, { $name: "s-lam", dict: lamProps });
      const methodcache = DotExpression(Identifier(self), "methodcache");
      const methodcacheAccess = BracketExpression(methodcache, Literal(method.dict.name));
      const valueObject = ObjectExpression([Property("value", Identifier(constId("$curriedmethod")))]);
      const body = [
        Var(self, { type: "ThisExpression"}),
        Var(constId("$methodgetter"),
          DotExpression(MethodCallExpression(Identifier(constId("Object")), "getOwnPropertyDescriptor",
                          [Identifier(self), Literal(method.dict.name)]), "get")),
        Var(constId("$curriedmethod"), curriedFunction),
        ExpressionStatement(AssignmentExpression(methodcache, ConditionalExpression(BinaryExpression("===", methodcache, Identifier(constId("undefined"))), ObjectExpression([]), methodcache))),
        ExpressionStatement(AssignmentExpression(methodcacheAccess, Identifier(constId("$methodgetter")))),
        ExpressionStatement(MethodCallExpression(Identifier(constId("Object")), "defineProperty",
            [Identifier(self), Literal(method.dict.name), valueObject])),
        ReturnStatement(Identifier(constId("$curriedmethod")))
      ];
      return FunctionExpression(constId("get"), [], BlockStatement(body));


      /*
rec $m = lam(self):
  if self.$$m === undefined:
    self.$$m = lam(): self.x end
    self.$$m.frommethod = true
    self.$$m.original = $m
  end
  self.m = self.$$m
  self.m
end

get ${method.name}() {
  var self = this;
  var $m = Object.getOwnPropertyDescriptor(self, ${method.name}).get;
  var $$m = function(${method.args.rest}) { ... ${method.bodystmts which uses self} ...}
  self.methodcache[${method.name}] = { original: $m };
  Object.defineProperty(self, ${method.name}, { value: $$m });
  return $$m;
}
      */
    }

    function compileObj(context, expr : Variant<A.Expr, 's-obj'>) : [J.Expression, Array<J.Statement>] {
      const fieldsAsArray = listToArray(expr.dict.fields);

      const fieldvs : Array<J.Property> = [], stmts = [];
      fieldsAsArray.forEach(f => {
        switch(f.$name) {
          case 's-method-field':
            fieldvs.push(Getter(f.dict.name, compileMethodDefinition(context, f)));
            return;
          case 's-data-field':
            const [val, compiledStmts] = compileExpr(context, f.dict.value);
            fieldvs.push(Property(f.dict.name, val));
            stmts.push(...compiledStmts);
            return;
          default:
            throw new InternalCompilerError("Not yet implemented: " + f.$name);
        }
      });
      return [  ObjectExpression(fieldvs), stmts ];
    }

    function pyretLookup(l : A.Srcloc, obj : J.Expression, field : string) : J.Expression {
      return DotExpression(obj, field);
    }

    type CompileResult = [J.Expression, Array<J.Statement>];

    function compileSrcloc(_context : any, l : A.Srcloc) : J.Expression {
      switch(l.$name) {
        case "builtin": return ArrayExpression([Literal(l.dict['module-name'])]);
        case "srcloc":
          return ArrayExpression([
            Literal(l.dict.source),
            Literal(l.dict['start-line']),
            Literal(l.dict['start-column']),
            Literal(l.dict['start-char']),
            Literal(l.dict['end-line']),
            Literal(l.dict['end-column']),
            Literal(l.dict['end-char']),
          ]);
      }
    }

    function compileModule(context, expr: Variant<A.Expr, "s-module">) : CompileResult {
      const fields = [];
      const stmts = [];
      const locs = [];
      listToArray(expr.dict['defined-values']).forEach(dv => {
        switch(dv.$name) {
          case 's-defined-value': {
            const [ val, fieldStmts ] = compileExpr(context, dv.dict['value']);
            const sloc = compileSrcloc(context, dv.dict.value.dict.l);
            fields.push(Property(dv.dict.name, val));
            stmts.push(...fieldStmts);
            locs.push(ObjectExpression([Property("name", Literal(dv.dict.name)), Property("srcloc", sloc)]));
            return;
          }
          case 's-defined-var': {
            const sloc = compileSrcloc(context, dv.dict.loc);
            fields.push(Property(dv.dict.name, Identifier(jsIdOf(dv.dict.id))));
            locs.push(ObjectExpression([Property("name", Literal(dv.dict.name)), Property("srcloc", sloc)]));
            return;
          }
        }
      });

      const [aExp, aStmts] = compileExpr(context, expr.dict.answer);
      const checkResults = rtMethod("$checkResults", []);
      const traces = rtMethod("$getTraces", []);

      const answer1 = freshId(compilerName("answer"))
      const answerVar = Var(answer1, aExp)

      const ans = ObjectExpression([
        ...fields,
        Property("$answer", Identifier(answer1)),
        Property("$checks", checkResults),
        Property("$traces", traces),
        Property("$locations", ArrayExpression(locs))
      ]);

      const assignAns = AssignmentExpression(DotExpression(Identifier(constId("module")), "exports"), ans);
      return [assignAns, [...aStmts, ...context.checkBlockTestCalls, answerVar, ...stmts]];
    }

    function compileOp(context, expr : Variant<A.Expr, "s-op">) : CompileResult {
      const [lv, lStmts] = compileExpr(context, expr.dict.left);
      const [rv, rStmts] = compileExpr(context, expr.dict.right);
      let ans;
      switch(expr.dict.op) {
        case "op+": ans = rtMethod("_plus", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op-": ans = rtMethod("_minus", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op*": ans = rtMethod("_times", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op/": ans = rtMethod("_divids", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op<": ans = rtMethod("_lessthan", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op>": ans = rtMethod("_greaterthan", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op<=": ans = rtMethod("_lessequal", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op>=": ans = rtMethod("_greaterequal", [lv, rv, rtField(NUMBER_ERR_CALLBACKS)]); break;
        case "op==": ans = CallExpression(rtField(EQUAL_ALWAYS), [lv, rv]); break;
        case "op<>": ans = UnaryExpression("!", CallExpression(rtField(EQUAL_ALWAYS), [lv, rv])); break;
        case "op<=>>": ans = CallExpression(rtField(IDENTICAL), [lv, rv]); break;
        case "opor": ans = LogicalExpression("||", lv, rv); break;
        case "opand": ans = LogicalExpression("&&", lv, rv); break;
        case "op^": ans = CallExpression(rv, [lv]); break;
        default: throw new TODOError(`Not yet implements: ${expr.dict.op}`);        
      }
      return [ans, [...lStmts, ...rStmts]];
    }

    function compileIf(context, branches: (A.IfBranch | A.IfPipeBranch)[], compiledElse: CompileResult) : CompileResult {
      const ans = Identifier(freshId(compilerName('ans')));
      const [elseV, elseStmts] = compiledElse;
      const elseBlock = BlockStatement([
        ...elseStmts,
        ExpressionStatement(AssignmentExpression(ans, elseV))
      ]);
      let block = elseBlock;
      for (let i = branches.length - 1; i >= 0; i--) {
        const branch = branches[i];
        const [testV, testStmts] = compileExpr(context, branch.dict.test);
        const [bodyV, bodyStmts] = compileExpr(context, branch.dict.body);
        block = BlockStatement([
          ...testStmts,
          IfStatement(testV, BlockStatement([
            ...bodyStmts,
            ExpressionStatement(AssignmentExpression(ans, bodyV))
          ]),
          block)
        ]);
      }
      return [ans, block.body];
    }

    function compileExpr(context, expr : A.Expr) : CompileResult {
      switch(expr.$name) {
        case 's-module':
          return compileModule(context, expr);
        case 's-block':
          return compileSeq(context, expr.dict.stmts);
        case 's-num':
          let numAns;
          if(typeof expr.dict.n === "number") {
            numAns = Literal(expr.dict.n);
          }
          else {
            numAns = rtMethod("_makeNumberFromString", [Literal(expr.dict.n.toString()), rtField(NUMBER_ERR_CALLBACKS)]);
          }
          return [numAns, []];
        case 's-str':
          return [Literal(expr.dict.s), []];
        case 's-bool':
          return [Literal(expr.dict.b), []];
        case 's-op':
          return compileOp(context, expr);
        case 's-prim-app':
          const [argvs, argstmts] = compileList(context, expr.dict.args);
          const primAns = CallExpression(rtField(expr.dict._fun), argvs);
          return [primAns, argstmts];
        case 's-srcloc':
          return [compileSrcloc(context, expr.dict.loc), []];
        case 's-when': {
          const nothing = compileExpr(context, { $name: 's-id', dict: { l: expr.dict.l, id: jsnames.sGlobal("nothing") }});
          return compileIf(context, 
            [{ $name: 's-if-branch', dict: { l: expr.dict.l, test: expr.dict.test, body: expr.dict.block }}],
            nothing
          );
        }
        case 's-if':
        case 's-if-pipe': {
          const srcloc = compileSrcloc(context, expr.dict.l);
          const type = (expr.$name === 's-if' ? 'if' : 'ask');
          const throwNoMatch = CallExpression(rtField("throwNoBranchesMatched"), [srcloc, Literal(type)]);
          return compileIf(context,
            listToArray<A.IfBranch | A.IfPipeBranch>(expr.dict.branches),
            [throwNoMatch, []]);
        }
        case 's-if-else': 
        case 's-if-pipe-else': {
          return compileIf(context,
            listToArray<A.IfBranch | A.IfPipeBranch>(expr.dict.branches),
            compileExpr(context, expr.dict._else));
        }
        case 's-obj':
          return compileObj(context, expr);
        case 's-dot': {
          const [objV, objStmts] = compileExpr(context, expr.dict.obj);
          return [pyretLookup(expr.dict.l, objV, expr.dict.field), objStmts]
        }
        case 's-extend': {
          const [objV, objStmts] = compileExpr(context, expr.dict.supe);
          const fieldsAsArray = listToArray(expr.dict.fields);

          const fieldvs = [], stmts = [];
          fieldsAsArray.forEach(f => {
            switch(f.$name) {
              case 's-method-field':
                fieldvs.push(Property(f.dict.name, ObjectExpression([
                  Property("get", compileMethodDefinition(context, f))
                ])));
                return;
              case 's-data-field':
                const [val, compiledStmts] = compileExpr(context, f.dict.value);
                fieldvs.push(Property(f.dict.name, ObjectExpression([ Property("value", val) ])));
                stmts.push(...compiledStmts);
                return;
              default:
                throw new InternalCompilerError("Not yet implemented: " + f.$name);
            }
          });
          return [rtMethod("$extend", [objV, ObjectExpression(fieldvs)]), stmts];
        }
        case 's-id':
          const b = context.postEnv.dict.bindings;
          const key = nameToKey(expr.dict.id);
          if(runtime.getField(b, "has-key-now").app(key) && 
             !(runtime.getField(b, "get-value-now").app(key).dict.origin.dict["new-definition"])) {
            context.freeBindings.set(key, runtime.getField(b, "get-value-now").app(key))
          }
          return [Identifier(jsIdOf(expr.dict.id)), []];
        case 's-id-letrec':
          const isSafe = expr.dict.safe;
          if(isSafe) {
            return [Identifier(jsIdOf(expr.dict.id)), []];
          }
          else {
            const id = Identifier(jsIdOf(expr.dict.id));
            return [ConditionalExpression(
              BinaryExpression("!==", id, Identifier(constId("undefined"))),
              id,
              rtMethod("$messageThrow", [compileSrcloc(context, expr.dict.l), Literal("Uninitialized letrec identifier")])
            ), []];
          }
        case 's-id-modref': {
          const [objv, objStmts] = compileExpr(context, { $name: "s-id", dict: { l: expr.dict.l, id: expr.dict.id }});
          return [ DotExpression(objv, expr.dict.name), objStmts ];
        }
        case 's-lam': {
          const [ bodyVal, bodyStmts ] = compileExpr(context, expr.dict.body);
          const bindArgs = expr.dict.args as A.List<Variant<A.Bind, "s-bind">>;
          const jsArgs = listToArray(bindArgs).map(a => jsIdOf(a.dict.id));
          return [FunctionExpression(jsIdOf(constId(expr.dict.name)), jsArgs,
            BlockStatement([...bodyStmts, ReturnStatement(bodyVal)])), []]
        }
        case 's-letrec':
        case 's-let-expr':
          const prelude = [];
          listToArray<A.LetrecBind | A.LetBind>(expr.dict.binds).forEach(v => {
            const [ val, vStmts ] = compileExpr(context, v.dict.value);
            switch(v.dict.b.$name) {
              case "s-tuple-bind":
                throw new InternalCompilerError("Broken invariant: s-tuple-bind in codegen");
              case "s-bind":
                prelude.push(...vStmts);
                prelude.push(Var(jsIdOf(v.dict.b.dict.id), val));
            }
          });
          const [ bv, bodyStmts ] = compileExpr(context, expr.dict.body);
          return [ bv, [...prelude, ...bodyStmts]];
        case 's-app-enriched': // TODO(joe): use info
        case 's-app': {
          const [fv, fstmts] = compileExpr(context, expr.dict._fun);
          const [argvs, argstmts] = compileList(context, expr.dict.args);
          return [ CallExpression(fv, argvs), [...fstmts, ...argstmts]];
        }
        default:
          throw new TODOError("Unhandled expression type: " + expr.$name);
      }
    }

    function getGlobals(prog : A.Program) : Set<string> {
      const globalNames = new Set<string>();
      visit<A.Name | A.Program>({
        "s-global": (_, g : (Variant<A.Name, "s-global">)) => {
          globalNames.add(g.dict.s);
        }
      }, prog);
      return globalNames;
    }

    function importToDep(i : A.ImportType) : CS.Dependency {
      switch(i.$name) {
        case 's-const-import': return { $name: 'builtin', dict: { modname: i.dict.mod }}
        case 's-special-import': return { $name: 'dependency', dict: {protocol: i.dict.kind, arguments: i.dict.args}}
      }
    }

    function depToKey(d : CS.Dependency) : string {
      switch(d.$name) {
        case 'dependency': return `${d.dict.protocol}(${listToArray(d.dict.arguments).join(", ")})`
        case 'builtin': return `builtin(${d.dict.modname})`;
      }
    }

    function createPrelude(prog : A.Program, provides, env, freeBindings : Map<string, CS.ValueBind>, options, importFlags) : Array<J.Statement> {

      function getBaseDir(source : string, buildDir : string) : [ string, string ] {
        let sourceHead = source.indexOf("://") + 3;
        const sourcePath = source.substring(sourceHead)
        const shorter = Math.min(sourcePath.length, buildDir.length)
        let cutoffIndex = 0;
        for(let i = 0; i < shorter; i += 1) {
          if(sourcePath[i] !== buildDir[i]) { cutoffIndex = i; break; }
        }
        return [ buildDir.substring(0, cutoffIndex), sourcePath ];
      }

      function getCompiledRelativePath(baseDir : string, source : string) {
        baseDir = P.resolve(baseDir);
        source = P.resolve(source);
        let projectRelativePath = P.dirname(source.substring(baseDir.length + 1));
        if(projectRelativePath === ".") { return "./"; }
        let parentPath = projectRelativePath.split("/").map(v => "../").join("");
        return parentPath;
      }

      const [ baseDir, absoluteSource ] = getBaseDir(provides.dict["from-uri"], options.dict["base-dir"]);
      const preAppendDir = getCompiledRelativePath(baseDir, absoluteSource);
      const relativePath = preAppendDir; // NOTE(joe): commented out in direct codegen: `preAppendDir + options.dict["runtime-path"]`

      // NOTE(joe/ben): we think we can simplify all the stuff above with the
      // right composition of P.relative and P.dirname, but the stuff above
      // works and this doesn't
//      const baseDir = options.dict["base-dir"];
//      const relativePath = P.relative(baseDir, P.dirname(uriToRealFsPath(provides.dict["from-uri"])));

      const imports = prog.dict.imports;

      function uriToRealFsPath(uri : string) : string {
        const index = uri.indexOf("://") + 3;
        return uri.substring(index) + ".js";
      }

      const runtimeBuiltinRelativePath : A.Option<string> = options.dict["runtime-builtin-relative-path"];

      function uriToImport(uri : string, name : A.Name) : Array<J.Statement> {
        if(uri.startsWith("builtin://")) {
          const builtinName = uriToRealFsPath(uri + ".arr");
          let thePath;
          switch(runtimeBuiltinRelativePath.$name) {
            case 'some': 
              thePath = runtimeBuiltinRelativePath.dict.value + builtinName;
              break;
            case 'none': 
              thePath = relativePath + "../builtin/" + builtinName;
              break;
          }
          return [
            Var(jsIdOf(name), CallExpression(Identifier(constId("require")), [Literal(thePath)])),
            ExpressionStatement(rtMethod("addModule", [Literal(uri), Identifier(jsIdOf(name))]))
          ];
        }
        else if(uri.startsWith("jsfile://") || uri.startsWith("file://")) {
          const targetPath = uriToRealFsPath(uri);
          const thisPath = uriToRealFsPath(provides.dict["from-uri"]);
          const jsRequirePath = P.relative(P.dirname(thisPath), targetPath);
          return [
            Var(jsIdOf(name), CallExpression(Identifier(constId("require")), [Literal("./" + jsRequirePath)])),
            ExpressionStatement(rtMethod("addModule", [Literal(uri), Identifier(jsIdOf(name))]))
          ];
        }
      }

      const globalNames = getGlobals(prog);
      const uriToLocalJsName = new Map<string, A.Name>();

      function importBuiltin(bindName : A.Name, name : string) {
        let thePath;
        switch(runtimeBuiltinRelativePath.$name) {
          case 'some': thePath = runtimeBuiltinRelativePath.dict.value + name; break;
          case 'none': thePath = relativePath + "../builtin/" + name; break;
        }
        return Var(bindName, CallExpression(Identifier(constId("require")), [Literal(thePath)]));
      }

      const runtimeImport = importBuiltin(RUNTIME, "runtime.js");

      const arrayImport =  importBuiltin(RUNTIME, "array.arr.js");
      const tableImport =  importBuiltin(RUNTIME, "tables.arr.js");
      const reactorImport =  importBuiltin(RUNTIME, "reactor.arr.js");

      const manualImports = [runtimeImport];
      if(importFlags["table-import"]) { manualImports.push(tableImport); }
      if(importFlags["reactor-import"]) {
        throw new TODOError("reactor.arr.js not implemented via flags");
          //manualImports.push(reactorImport);
      }
      if(importFlags["array-import"]) {
        throw new TODOError("array.arr.js not implemented via flags");
          //manualImports.push(arrayImport);
      }

      const explicitImports = listToArray(imports).map(importStmt => {
        switch(importStmt.$name) {
          case 's-import':
            const depKey = depToKey(importToDep(importStmt.dict.file));
            // TODO(joe): this punched through "uri-by-dep-key" because of flatness concerns
            // This should use a clean CompileEnv interface method
            let uri = runtime.getField(env.dict["my-modules"], "get-value").app(depKey);
            switch(options.dict["compile-mode"].$name) {
              case 'cm-normal': break;
              case 'cm-builtin-stage-1':
              case 'cm-builtin-general': uri = "builtin://" + P.basename(uri, ".arr"); break;
            }
            uriToLocalJsName.set(uri, importStmt.dict.name);
            return uriToImport(uri, importStmt.dict.name);
          default:
            return [];
            //throw new InternalCompilerError("Codegen requires s-import only " + JSON.stringify(importStmt));
        }
      }).reduce((l1, l2) => l1.concat(l2), []);

      function envUriByValueNameValue(env, name) {
        // TODO(joe): this punched through "uri-by-value-name-value" because of flatness concerns
        // This should use a clean CompileEnv interface method
        return runtime.getField(env.dict.globals.dict.values, "get-value").app(name).dict["uri-of-definition"];
      }

      const nonImportedGlobalNames = [...(globalNames.keys())].filter(g => {
        return !(uriToLocalJsName.has(envUriByValueNameValue(env, g)));
      });

      const implicitImports = [];
      nonImportedGlobalNames.forEach(g => {
        const uri = envUriByValueNameValue(env, g);
        if (!uriToLocalJsName.has(uri)) {
          const newName = freshId(compilerName("G"));
          uriToLocalJsName.set(uri, newName);
          implicitImports.push(...uriToImport(uri, newName));
        }
      });

      const importStmts = [...manualImports, ...explicitImports, ...implicitImports];

      /* NOTE(joe): this was no-op code that produces a list and doesn't use it
      for CL.map_list(g from global-names.keys-list-now()):
        uri = env.uri-by-value-name-value(g)
        imported-as = uri-to-local-js-name.get-value-now(uri)
        J.j-var(js-id-of(A.s-global(g)), J.j-dot(j-id(js-id-of(imported-as)), g))
      end
      */

      const fromModules = [...freeBindings.values()].map(binding => {
        const uri = binding.dict["origin"].dict["uri-of-definition"];
        const name = nameToName(binding.dict["origin"].dict["original-name"]);
        return Var(jsIdOf(binding.dict["atom"]), rtMethod("getModuleValue", [Literal(uri), Literal(name)]));
      });

      return [...importStmts, ...fromModules];
    }

    function visit<T extends { $name: string, dict: {} }>(v : Partial<Record<T["$name"], any>>, d : T) {
      if(typeof d !== "object" || !("$name" in d)) { throw new Error("Visit failed: " + JSON.stringify(d)); }
      if(d.$name in v) { v[d.$name](v, d); }
      else {
        for(const [k, subd] of Object.entries(d.dict)) {
          if(typeof subd === 'object' && "$name" in subd) {
            visit(v, subd as any);
          }
        }
      }
    }

    function map<T extends { $name: string, dict: {} }, A extends T>(v : Partial<Record<T["$name"], any>>, d : A) : A {
      if(typeof d !== "object" || !("$name" in d)) { throw new Error("Map failed: " + JSON.stringify(d)); }
      if(d.$name in v) { return v[d.$name](v, d); }
      else {
        const newObj : typeof d = Object.create(Object.getPrototypeOf(d));
        for(const [k, meta] of Object.entries(d)) {
          if(k !== "dict") { newObj[k] = meta; }
        }
        newObj.dict = Object.create(Object.getPrototypeOf(d.dict));
        for(const [k, subd] of Object.entries(d.dict)) {
          if(typeof subd === 'object' && "$name" in subd) {
            const result = map(v, subd as any);
            newObj.dict[k] = result;
          }
          else {
            newObj.dict[k] = subd;
          }
        }
        return newObj;
      }
    }

    function assertMapIsDoingItsJob(prog : A.Program) {
      const after = map<A.Program, A.Program>({}, prog);
      if(prog === after) { throw new InternalCompilerError("AST map visitor returned an identical object"); }
      return after;
    }

    let importFlags = {
      'table-import': false,
      'array-import': false,
      'reactor-import': false
    };
    function compileProgram(prog : A.Program, uri : string, env : any, postEnv : any, provides : any, options : any) : PyretObject {
      const translatedDatatypeMap = new Map();   // TODO(joe) process from stringdict
      const fromUri = provides.dict['from-uri']; // TODO(joe) handle phases builtin-stage*
      const freeBindings = new Map<string, CS.ValueBind>();            // NOTE(joe) this starts empty in the mainline compiler

      // TODO(joe): remove this when we are 100% confident that map doesn't fudge with the AST
      prog = assertMapIsDoingItsJob(prog);

      const [ans, stmts] = compileExpr({
        uri: fromUri,
        options: options,
        provides: provides,
        datatypes: translatedDatatypeMap,
        env: env,
        postEnv: postEnv,
        freeBindings: freeBindings,
        checkBlockTestCalls: []
      }, prog.dict.block);

      const prelude = createPrelude(prog, provides, env, freeBindings, options, importFlags);

      const moduleBody = Program([...prelude, ...stmts, ReturnStatement(ans)]);
      const moduleAndMap = {
        map: "",
        code: escodegen.generate(moduleBody)
      };
      return runtime.makeObject({
        theModule: moduleAndMap.code,
        theMap: moduleAndMap.map
      });
    }

    return runtime.makeModuleReturn({
      'compile-program': runtime.makeFunction(compileProgram)
    }, {});

  }
})