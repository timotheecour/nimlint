import ../compiler/[ast, idents, msgs, syntaxes, options, pathutils]
import std/[os, parseutils]
from ../compiler/astalgo import debug
from ../compiler/renderer import renderTree

type
  PrettyOptions* = object
    indWidth*: Natural
    maxLineLen*: Positive

  HintStateKind* = enum
    # doc comments
    hintBackticks, hintCodeBlocks, hintCapitialize
    # functions
    hintFunc, hintIsMainModule
    # testament
    hintExitcode
    hintAssert

  HintState* = object
    kind: HintStateKind
    info: tuple[row, col: int]

# code block => runnableExamples
# proc + noSideEffect => func
# assert in a test file => doAssert
# isMainModule in stdlib => recommend moving to tests/stdlib/tfoo.nim
# double backticks => single backticks
# capitalize the fist letter
# lots of testament specific checks (eg exitcode: 0 usually useless)

proc initHintState(kind: HintStateKind, row, col: int): HintState =
  HintState(kind: kind, info: (row, col))

const
  SpecialChars = {'\r', '\n', '`'}
  testsPath = "tests"

proc clean(conf: ConfigRef, n: PNode, hintstable: var seq[HintState]) =
  if n.comment.len != 0:
    var line = n.info.line
    var start = 0
  case n.kind
  of nkImportStmt, nkExportStmt, nkCharLit..nkUInt64Lit,
      nkFloatLit..nkFloat128Lit, nkStrLit..nkTripleStrLit:
    discard
  of nkWhenStmt:
    # Handles the most common case
    # {
    #   "kind": "nkWhenStmt",
    #   "typ": "nil",
    #   "sons": [{
    #     "kind": "nkElifBranch",
    #     "typ": "nil",
    #     "sons": [{
    #       "kind": "nkIdent",
    #       "typ": "nil",
    #       "ident": "isMainModule"
    #     }, {
    #       "kind": "nkStmtList",
    #       "typ": "nil"
    if n.len > 0 and n[0].kind == nkElifBranch:
      let son = n[0]
      if son[0].kind == nkIdent and son[0].ident.s == "isMainModule":
        hintsTable.add initHintState(hintIsMainModule, n.info.line.int, n.info.col.int)
  of nkIdent, nkSym:
    discard
  else:
    for s in n.sons:
      clean(conf, s, hintsTable)

proc prettyPrint*(infile, outfile: string, hintsTable: var seq[HintState]) =
  var conf = newConfigRef()
  let fileIdx = fileInfoIdx(conf, AbsoluteFile infile)
  let f = splitFile(outfile.expandTilde)
  conf.outFile = RelativeFile f.name & f.ext
  conf.outDir = toAbsoluteDir f.dir
  var parser: Parser
  var cache = newIdentCache()

  if setupParser(parser, fileIdx, cache, conf):
    var ast = parseFile(conf.projectMainIdx, cache, conf)
    clean(conf, ast, hintsTable)
    closeParser(parser)

proc main*(fileInput, fileOutput: string) =
  # var outfile, outdir: string

  # var infiles = newSeq[string]()
  # var outfiles = newSeq[string]()

  # var backup = false
    # when `on`, create a backup file of input in case
    # `prettyPrint` could over-write it (note that the backup may happen even
    # if input is not actually over-written, when nimpretty is a noop).
    # --backup was un-documented (rely on git instead).

  var hintsTable: seq[HintState]
  prettyPrint(fileInput, fileOutput, hintsTable)

  for item in hintsTable:
    case item.kind
    of HintStateKind.hintIsMainModule:
      echo item
    else:
      discard

when isMainModule:
  var x = 13
  main("example.nim", "out.nim")
