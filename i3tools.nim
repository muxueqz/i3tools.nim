import json
import net
import strutils
import os
import osproc
import tables
import std/[sequtils]
import std/[options]

import i3ipc
import myi3_status

let app_id_mapping = {
  "Google-chrome": "google-chrome",
  "x-terminal-emulator": "terminal"
}.toTable

var focused_workspace: int

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

proc extract_windows*(workspace: Node): seq[Node] =
  result = @[]

  proc process_node(node: var Node) =
    node.workspace = workspace.id.some()
    if node.focused:
      focused_workspace = workspace.id

  var stack = concat(workspace.floating_nodes, workspace.nodes)
  while stack.len > 0:
    var node = stack.pop()
    if concat(node.floating_nodes, node.nodes).len == 0:
      process_node(node)
      result.add node
    else:
      for child in concat(node.floating_nodes, node.nodes):
        var c = child
        c.workspace = workspace.id.some()
        stack.add(c)

proc get_windows(current_workspace: bool = false): seq[Node] =
  let data = ipc_query(get_tree).to(TreeData)

  var workspace_windows = initTable[int, seq[Node]]()
  result = @[]
  for output in data.nodes:
    if output.`type` == "output":
      for workspace in output.nodes:
        if workspace.`type` == "workspace":
          workspace_windows[workspace.id] = workspace.extract_windows
  if current_workspace:
    return workspace_windows[focused_workspace]
  return workspace_windows.values.toSeq.concat


proc select_window(current_workspace: bool = false) =
  let r = get_windows(current_workspace)
  var dmenu_str = ""
  for n, i in r:
    var icon = "shellscript"
    echo i
    if i.app_id.isNone() and i.window_properties.isSome():
      icon = i.window_properties.get.class
    else:
      icon = i.app_id.get
    icon = app_id_mapping.getOrDefault(icon, icon)
    dmenu_str.add icon[0 ..< icon.len.min(18)] & "\t" & i.name      & "\0icon\x1f" & icon & "\n"

  let cmd = getEnv("DMENU_CMD",
    "fuzzel --dmenu --index -w 80 --counter --prompt \"Window > \"")
  let (output, exitCode) = execCmdEx(cmd, input = dmenu_str, options = {})
  var selected = output.strip
  if "fuzzel " in cmd:
    if exitCode > 10 and exitCode < 20:
      selected = $(exitCode - 10)
  if selected != "":
    let
      idx = parseInt(selected)
      win_id= r[idx].id
    discard ipc_query(command, "[con_id=" & $win_id & "] focus")

when isMainModule:
  let params = commandLineParams()
  if params.len < 1:
    quit(-1)
  let func_name = params[0]
  case func_name
  of "window":
    select_window(false)
  of "windowcd":
    select_window(true)
  of "switch-workspace":
    switch_workspace(params)
  of "i3status":
    myi3_status.get_status()
  else:
    discard
