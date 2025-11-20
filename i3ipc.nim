import json
import net
import os
import streams
import std/[options]

const
  magic = ['i', '3', '-', 'i', 'p', 'c'] ## prefix for msgs to/from server
type
  Header = object
    magic*: array[magic.len, char]
    length*: int32
    mtype*: int32
const I3_IPC_MAGIC = "i3-ipc"

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

proc ipc_query*(req: I3MessageType, msg: string = ""): JsonNode =
  let ans = i3_msg(req.uint32, msg)
  return parseJson(ans)

type
  Node* = object
    id*: int
    name*: string
    app_id*: Option[string]
    focused*: bool
    `type`*: string
    nodes*: seq[Node]
    floating_nodes*: seq[Node]
    workspace*: Option[int]
    window_properties*: Option[Window_properties]

  TreeData* = object
    nodes*: seq[Node]

# "window_properties": {
#   "class": "st-256color",
#   "instance": "st-256color",
#   "title": "st",
#   "transient_for": null
# }
  Window_properties* = object
    # instance*: string
    instance*, `class`*, title*: string
type
  WindowInfo* = object
    id*: int
    name*: string
    app_id*: string
    focused*: bool
    `type`*: string
    nodes*: seq[WindowInfo]

  Workspace* = object
    id*: int
    name*: string
    `type`*: string
    nodes*: seq[WindowInfo]

  Rect = object
    x, y, width*, height*: int

  Output* = object
    name*: string
    active*: bool
    primary*: bool
    rect*: Rect

