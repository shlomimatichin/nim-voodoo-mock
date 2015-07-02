import macros
import strutils
import os

macro runAll(): stmt =
    var source = ""
    source &= """echo "ls $TESTS_DIR" """ & "\n"
    var filesInTestDir = split(staticExec("""ls $TESTS_DIR""", "\n"))
    for filename in filesInTestDir:
        if not filename.startsWith("test_"):
            continue
        if not filename.endsWith(".nim"):
            continue
        echo "Found test suite: " & filename
        source &= "include " & os.splitFile(filename).name & "\n"
    result = parseStmt(source)

runAll()
