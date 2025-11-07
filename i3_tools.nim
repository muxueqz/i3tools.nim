import json
import net
import strutils
import os
import osproc
import tables
import streams


const
  magic = ['i', '3', '-', 'i', 'p', 'c'] ## prefix for msgs to/from server
type
  Header = object
    magic*: array[magic.len, char]
    length*: int32
    mtype*: int32
const I3_IPC_MAGIC = "i3-ipc"

# type
#   # I3MessageType* {.pure.} = enum
#   I3MessageType = enum
#     command = 0, get_workspaces, subscribe, get_outputs = 3, get_tree = 4,
#     get_marks, get_bar_config, get_version
type
  I3MessageType* {.pure.} = enum
    command,
    get_workspaces,
    subscribe,
    get_outputs,
    get_tree,
    get_marks,
    get_bar_config,
    get_version

let app_id_mapping = {
  "Google-chrome": "google-chrome",
  "x-terminal-emulator": "terminal"
}.toTable

var focused_workspace: int

proc i3_msg(message_type: uint32, payload: string = ""): string =
  let sway_socket = getEnv("SWAYSOCK")
  let i3_socket = getEnv("I3SOCK")
  let ipc_socket_path = if sway_socket != "": sway_socket else: i3_socket
  if ipc_socket_path == "":
    raise newException(ValueError, "Could not find SWAYSOCK or I3SOCK in environment")

  let sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  sock.connectUnix(ipc_socket_path)

  let payload_bytes = payload
  let message_length = payload_bytes.len.uint32

  var  ss = newStringStream()
  # var header = Header(magic: magic,
  #   length: cast[Header.length](payload.len),
  #   mtype: cast[Header.mtype](1))
  ss.write(magic)
  ss.write(message_length)
  ss.write(message_type)
  ss.write(payload_bytes)

  sock.send(ss.data)

  var response_header = newString(14)
  let recv_header_len = sock.recv(response_header, 14)
  if recv_header_len != 14:
    raise newException(IOError, "Failed to receive response header")

  let magic = response_header[0..5]
  if magic != I3_IPC_MAGIC:
    raise newException(ValueError, "Invalid IPC magic in response")

  let response_length = uint32(response_header[6]) or (uint32(response_header[7]) shl 8) or
                        (uint32(response_header[8]) shl 16) or (uint32(response_header[9]) shl 24)

  #
  var response_payload = newString(response_length.int)
  let recv_payload_len = sock.recv(response_payload, response_length.int)
  if recv_payload_len != response_length.int:
    raise newException(IOError, "Failed to receive response payload")

  sock.close()
  return response_payload

# proc ipc_query(req: uint32, msg: string = ""): JsonNode =
proc ipc_query(req: I3MessageType, msg: string = ""): JsonNode =
  let ans = i3_msg(req.uint32, msg)
  return parseJson(ans)

proc switch_workspace(argv: seq[string]) =
  if argv.len != 2:
    echo "Usage: switch-workspace name-of-workspace"
    quit(-1)

  let newworkspace = argv[1]

  var active_display: string = ""
  var old_display: string = ""

  let workspaces = ipc_query(I3MessageType.get_workspaces)
  for w in workspaces.items:
    if w["focused"].getBool:
      active_display = w["output"].getStr
    if $w["num"].getInt == newworkspace:
      old_display = w["output"].getStr

  if active_display == old_display:
    let msg = "workspace number " & newworkspace
    echo ipc_query(command, msg)
    quit(0)

  echo ipc_query(command, "workspace number " & newworkspace & ";")
  echo ipc_query(command, "move workspace to output " & active_display)

proc extract_nodes_iterative(workspace: JsonNode): seq[JsonNode] =
  result = @[]

  proc process_node(node: JsonNode, workspace: JsonNode) =
    node["workspace"] = %* workspace["id"].getInt
    if node.getOrDefault("focused").getBool:
      focused_workspace = workspace["id"].getInt

  let floating_nodes = workspace.getOrDefault("floating_nodes").getElems
  for floating_node in floating_nodes:
    process_node(floating_node, workspace)
    result.add floating_node

  var nodes = workspace.getOrDefault("nodes").getElems
  var i = 0
  while i < nodes.len:
    let node = nodes[i]
    i += 1
    if node.getOrDefault("nodes").len == 0:
      process_node(node, workspace)
      result.add node
    else:
      for inner_node in node["nodes"].getElems:
        inner_node["workspace"] = %* workspace["id"].getInt  # Consistent with id
        nodes.add inner_node

# type
#   Workspace = object
#     id: int
#     age: int
#     `type`: Option[string]

proc get_windows(only_workspace: bool = false): seq[JsonNode] =
  let data = ipc_query(get_tree)

  var workspace_windows = initTable[int, seq[JsonNode]]()
  for output in data["nodes"].getElems:
    if output["type"].getStr == "output":
      let workspaces = output["nodes"].getElems
      for workspace in workspaces:
        if workspace["type"].getStr == "workspace":
          let workspace_id = workspace["id"].getInt
          let windows = extract_nodes_iterative(workspace)
          workspace_windows[workspace_id] = windows

  result = @[]
  for k, v in workspace_windows:
    if only_workspace and k != focused_workspace:
      continue
    result.add v

proc select_window(argv: seq[string]) =
  var only_workspace = false
  if argv.len > 1 and argv[1] == "current_workspace":
    only_workspace = true

  let r = get_windows(only_workspace)
  var dmenu_str = ""
  for n, i in r:
    var icon = i.getOrDefault("app_id").getStr
    # if icon == "":
      # echo i
      # icon = i.getOrDefault("window_properties", %*{})
      # icon = i.getOrDefault("window_properties", %*{}).getOrDefault("class", %*"").getStr
    icon = app_id_mapping.getOrDefault(icon, icon)
    let name = i["name"].getStr
    dmenu_str.add icon & "\t" & name & "\0icon\x1f" & icon & "\n"

  let cmd = "fuzzel --dmenu --index -w 80 --counter --prompt \"Window > \""
  let (output, exitCode) = execCmdEx(cmd, input = dmenu_str)
  var selected = output.strip
  if exitCode > 10 and exitCode < 20:
    selected = $(exitCode - 10)
  if selected != "":
    let idx = parseInt(selected)
    let selected_window = r[idx]
    let window_id = selected_window["id"].getInt
    discard execCmd("swaymsg [con_id=" & $window_id & "] focus")

when isMainModule:
  let params = commandLineParams()
  if params.len < 1:
    quit(-1)
  let func_name = params[0]
  case func_name
  of "select-window":
    select_window(params)
  of "switch-workspace":
    switch_workspace(params)
  else:
    discard
