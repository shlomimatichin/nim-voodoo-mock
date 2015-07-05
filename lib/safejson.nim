import json
import macros

export json.JsonNode
export json.`%*`
export json.`%`
export json.newJObject
export json.newJString
export json.newJArray
export json.`[]=`
export json.`$`
export json.add

proc `[]`*(node: JsonNode; name: string): JsonNode {.raises: [], tags: [].} =
    if node == nil:
        return nil
    return json.`[]`(node, name)

proc getNum*(node: JsonNode; default: BiggestInt = 0): BiggestInt {.raises: [], tags: [].} =
    if node == nil:
        return default
    return json.getNum(node, default)

proc getStr*(node: JsonNode; default: string = ""): string {.raises: [], tags: [].} =
    if node == nil:
        return default
    return json.getStr(node, default)
