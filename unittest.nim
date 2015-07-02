# based on the standard unittest module, but hyped up

import
    macros

when declared(stdout):
    import os

when not defined(ECMAScript):
    import terminal
    system.addQuitProc(resetAttributes)

type
    TestStatus* = enum OK, FAILED
    OutputLevel* = enum PRINT_ALL, PRINT_FAILURES, PRINT_NONE
    OutputFormat* = enum PRINT_TEST, PRINT_SUITE_TEST

var
    abortOnError* {.threadvar.}: bool
    outputLevel* {.threadvar.}: OutputLevel
    outputFormat* {.threadvar.}: OutputFormat
    colorOutput* {.threadvar.}: bool

    checkpoints {.threadvar.}: seq[string]
    currentTestSuite*: string

checkpoints = @[]

template testSetupIMPL*: stmt {.immediate, dirty.} = discard
template testTeardownIMPL*: stmt {.immediate, dirty.} = discard

proc shouldRun(testName: string): bool =
    result = true

template suite*(name: expr, body: stmt): stmt {.immediate, dirty.} =
    block:
        currentTestSuite = name


        template setup*(setupBody: stmt): stmt {.immediate, dirty.} =
            template testSetupIMPL: stmt {.immediate, dirty.} = setupBody

        template teardown*(teardownBody: stmt): stmt {.immediate, dirty.} =
            template testTeardownIMPL: stmt {.immediate, dirty.} = teardownBody

        body

proc testDone(name: string, s: TestStatus) =
    if s == FAILED:
        programResult += 1

    if outputLevel == PRINT_NONE:
        return
    if outputLevel == PRINT_FAILURES and s != FAILED:
        return
    var finalName = name
    if outputFormat == PRINT_SUITE_TEST:
        finalName = currentTestSuite & ":    " & name
    var bracketedStatus = "[" & $s & "] "
    when not defined(ECMAScript):
        if colorOutput and not defined(ECMAScript):
            var color = (if s == OK: fgGreen else: fgRed)
            styledEcho styleBright, color, bracketedStatus, fgWhite, finalName
        else:
            echo bracketedStatus, finalName
    else:
        echo bracketedStatus, finalName

template test*(name: expr, body: stmt): stmt {.immediate, dirty.} =
    bind shouldRun, checkpoints, testDone

    if shouldRun(name):
        checkpoints = @[]
        var testStatusIMPL {.inject.} = OK

        try:
            testSetupIMPL()
            body

        except:
            checkpoint("Unhandled exception: " & getCurrentExceptionMsg())
            echo getCurrentException().getStackTrace()
            fail()

        finally:
            testTeardownIMPL()
            testDone name, testStatusIMPL

proc checkpoint*(msg: string) =
    checkpoints.add(msg)
    # TODO: add support for something like SCOPED_TRACE from Google Test

template fail* =
    bind checkpoints
    for msg in items(checkpoints):
        # this used to be 'echo' which now breaks due to a bug. XXX will revisit
        # this issue later.
        stdout.writeln msg

    when not defined(ECMAScript):
        if abortOnError: quit(1)

    when declared(testStatusIMPL):
        testStatusIMPL = FAILED
    else:
        programResult += 1

    checkpoints = @[]

macro check*(conditions: stmt): stmt {.immediate.} =
    let checked = callsite()[1]

    var
        argsAsgns = newNimNode(nnkStmtList)
        argsPrintOuts = newNimNode(nnkStmtList)
        counter = 0

    template asgn(a, value: expr): stmt =
        var a = value # XXX: we need "var: var" here in order to
                      # preserve the semantics of var params

    template print(name, value: expr): stmt =
        when compiles(string($value)):
            checkpoint(name & " was " & $value)

    proc inspectArgs(exp: NimNode) =
        for i in 1 .. <exp.len:
            if exp[i].kind notin nnkLiterals:
                inc counter
                var arg = newIdentNode(":p" & $counter)
                var argStr = exp[i].toStrLit
                var paramAst = exp[i]
                if exp[i].kind in nnkCallKinds: inspectArgs(exp[i])
                if exp[i].kind == nnkExprEqExpr:
                    # ExprEqExpr
                    #     Ident !"v"
                    #     IntLit 2
                    paramAst = exp[i][1]
                argsAsgns.add getAst(asgn(arg, paramAst))
                argsPrintOuts.add getAst(print(argStr, arg))
                if exp[i].kind != nnkExprEqExpr:
                    exp[i] = arg
                else:
                    exp[i][1] = arg

    case checked.kind
    of nnkCallKinds:
        template rewrite(call, lineInfoLit: expr, callLit: string, argAssgs, argPrintOuts: stmt): stmt =
            block:
                argAssgs
                if not call:
                    checkpoint(lineInfoLit & ": Check failed: " & callLit)
                    argPrintOuts
                    fail()

        var checkedStr = checked.toStrLit
        inspectArgs(checked)
        result = getAst(rewrite(checked, checked.lineinfo, checkedStr, argsAsgns, argsPrintOuts))

    of nnkStmtList:
        result = newNimNode(nnkStmtList)
        for i in countup(0, checked.len - 1):
            if checked[i].kind != nnkCommentStmt:
                result.add(newCall(!"check", checked[i]))

    else:
        template rewrite(Exp, lineInfoLit: expr, expLit: string): stmt =
            if not Exp:
                checkpoint(lineInfoLit & ": Check failed: " & expLit)
                fail()

        result = getAst(rewrite(checked, checked.lineinfo, checked.toStrLit))

template require*(conditions: stmt): stmt {.immediate, dirty.} =
    block:
        const AbortOnError {.inject.} = true
        check conditions

macro expect*(exceptions: varargs[expr], body: stmt): stmt {.immediate.} =
    let exp = callsite()
    template expectBody(errorTypes, lineInfoLit: expr, body: stmt): NimNode {.dirty.} =
        try:
            body
            checkpoint(lineInfoLit & ": Expect Failed, no exception was thrown.")
            fail()
        except errorTypes:
            discard

    var body = exp[exp.len - 1]

    var errorTypes = newNimNode(nnkBracket)
    for i in countup(1, exp.len - 2):
        errorTypes.add(exp[i])

    result = getAst(expectBody(errorTypes, exp.lineinfo, body))


when declared(stdout):
    proc getEnv(key: string): string = os.getEnv(key).string
    proc existsEnv(key: string): bool = os.existsEnv(key)
else:
    proc getEnv(key: string): string = ""
    proc existsEnv(key: string): bool = false

template fromEnvironment(enumeration: typedesc, key: string): expr =
    var result: enumeration
    for opt in countup(low(enumeration), high(enumeration)):
        if $opt == getEnv(key):
            result = opt
    result
outputLevel = fromEnvironment(OutputLevel, "NIMTEST_OUTPUT_LEVEL")
outputFormat = fromEnvironment(OutputFormat, "NIMTEST_OUTPUT_FORMAT")
abortOnError = existsEnv("NIMTEST_ABORT_ON_ERROR")
colorOutput = not existsEnv("NIMTEST_NO_COLOR")
