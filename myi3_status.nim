import json
import std/strformat
import std/strutils
import std/[times, os]
import math
import std/tables
import strscans
import i3ipc

var DEFAULT_PROCPATH = "/proc"

const
  updateFile = "/tmp/update_display"
  head = """{"version":1,"click_events":true,"stop_signal":0,"cont_signal":0}
["""

proc getWidth(): int =
  let outputs = to(ipc_query(get_outputs), seq[Output])
  for output in outputs:
    if output.primary:
      return output.rect.width
  return outputs[0].rect.width

var
  module_count = 3
  lastIdle = 0
  lastTotal = 0

proc getCpuUsage(): int =
  let fd = open("/proc/stat", fmRead)
  defer: close(fd)
  let line = fd.readLine()   # e.g. "cpu  1223 34 875 12345 67 8 9"

  if not line.startsWith("cpu "):
    return 0

  var
    user, nice, system, idle, iowait, irq, softirq, steal, guest, guestNice: int

  # Parse up to 10 fields, compatible with various kernel versions
  discard scanf(line, "cpu$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i$s$i",
                user, nice, system, idle, iowait, irq, softirq, steal, guest, guestNice)

  let total = user + nice + system + idle + iowait + irq + softirq + steal
  let idleDelta = idle - lastIdle
  let totalDelta = total - lastTotal
  lastIdle = idle
  lastTotal = total

  if totalDelta == 0:
    return 0

  return int((1 - idleDelta.float / totalDelta.float) * 100)

proc getMemUsage(): int =
  var meminfo = initTable[string, int]()
  for line in lines("/proc/meminfo"):
    var
      key: string
      val: int
    # Example line: "MemTotal:       16301556 kB"
    if scanf(line, "$w:$s$i", key, val):
      meminfo[key] = val

  let
    total = meminfo.getOrDefault("MemTotal")
    free = meminfo.getOrDefault("MemFree") +
             meminfo.getOrDefault("Buffers") +
             meminfo.getOrDefault("Cached")

  if total == 0:
    return 0
  return int((total - free) * 100 div total)

proc getBatteryInfo(devpath: string, useEnergyFullDesign: bool): string =
  proc getBatteryInfoReal(devpath: string, useEnergyFullDesign: bool): string =
    var
      ueventData = initTable[string, string]()
      energyFull, energyNow, powerNow: float
      flag = ""
      remTime = 0.0

    try:
      for line in lines(devpath / "uevent"):
        var key, val: string
        # Example: "POWER_SUPPLY_ENERGY_NOW=123456789"
        if scanf(line, "POWER_SUPPLY_$w=$*", key, val):
          ueventData[key.toLowerAscii()] = val

      template f(k: string): string = ueventData.getOrDefault(k)

      if f("energy_full") != "":
        energyFull = parseFloat(f("energy_full"))
      if f("energy_now") != "":
        energyNow = parseFloat(f("energy_now"))
      if f("power_now") != "":
        powerNow = parseFloat(f("power_now"))

      # Handle charge-based batteries
      if f("charge_full") != "":
        let voltageNow = parseFloat(f("voltage_now"))
        energyFull = parseFloat(f("charge_full")) * voltageNow / 1_000_000
        energyNow = parseFloat(f("charge_now")) * voltageNow / 1_000_000
        if f("current_now") != "":
          powerNow = parseFloat(f("current_now")) * voltageNow / 1_000_000

      let status = f("status")
      var energyFullDesign = energyFull
      if useEnergyFullDesign and f("energy_full_design") != "":
        energyFullDesign = parseFloat(f("energy_full_design"))

      let capacity = min(int(energyNow / energyFullDesign * 100 + 0.5), 100)

      if powerNow != 0:
        if status == "Charging":
          remTime = (energyFull - energyNow) / powerNow
          flag = "↑"
        elif status in ["Discharging", "Not charging"]:
          remTime = energyNow / powerNow
          flag = "↓"

      return &"{flag} {capacity}%:{remTime.int}H"
    except:
      return "battery: unknown"

  return getBatteryInfoReal(devpath, useEnergyFullDesign)

proc get_status*() =
  echo(head)
  os.sleep(1*1000)
  var
    used_width = module_count*12*16 - 16*8 # module_width - workspace_width
    min_width = getWidth() - used_width 
    dev = "CMB0"
    devpath = "/sys/class/power_supply/" & dev
    status_array: seq[string]
    count = 5
  for i in 0..module_count:
    status_array.add("")
  while true:
    if fileExists(updateFile):
      removeFile(updateFile)
      min_width = getWidth() - used_width 
    var
      item_num = 0
      full_text = times.now().format("yyyy-MM-dd ddd HH:mm:ss")
      status_item = fmt"""{{"full_text": "{full_text}", "name" : "datetime", "align":"center", "min_width": {min_width}}}"""

    status_array[item_num] = status_item
    inc item_num

    if count >= 5:
      status_array[item_num] = fmt"""{{ "full_text": " cpu {getCpuUsage():02}% ", "name": "cpu" }}"""
      inc item_num
      status_array[item_num] = fmt"""{{ "full_text": " mem {getMemUsage():02}% ", "name": "mem" }}"""
      inc item_num
      var battery_info = getBatteryInfo(devpath, false)
      status_array[item_num] = fmt"""{{ "full_text": " {battery_info} ", "name": "battery" }}"""
      inc item_num
      count = 0

    var status_line = status_array.join(",")
    echo fmt"[{status_line}],"
    os.sleep(1*1000)
    inc count

when isMainModule:
  get_status()
