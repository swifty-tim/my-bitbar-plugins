#!/usr/bin/env xcrun swift

/*
 * <bitbar.title>Bluetooth Battery</bitbar.title>
 * <bitbar.version>v1.0</bitbar.version>
 * <bitbar.author>Timothy Barnard</bitbar.author>
 * <bitbar.author.github>collegboi</bitbar.author.github>
 * <bitbar.desc>Displays a list of bluetooth devices and battery status</bitbar.desc>
 * <bitbar.dependencies>Xcode,swift</bitbar.dependencies>
 */

import Foundation

typealias Color = (red : UInt, green : UInt, blue : UInt)
var stringSpacing: Int = 0

struct Device {
    var name: String
    var colorString: String
    var statusString: String
    var ansiColorString: String
    var connected: Bool
    var paired: Bool
    var extraData: [String]
    
    init() {
        name = ""
        colorString = ""
        statusString = ""
        ansiColorString = ""
        connected = false
        paired = false
        extraData = [String]()
    }
}


func shell(args: String...) -> String {
    let task = Process()
    task.launchPath = "/bin/bash"
    task.arguments = ["-c"] + args
    
    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output: String = String(data: data, encoding: String.Encoding.utf8)!
    
    return output.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
}

func rgb(r : UInt, g : UInt , b : UInt) -> Color {
    return (red: r, green: g, blue: b)
}

let colors = [
    rgb(r: 231, g: 76, b: 60),
    rgb(r: 241, g: 196, b: 15),
    rgb(r: 0, g: 177, b: 106)
]

func linear(initial: UInt, next: UInt, percent: Double) -> Double {
    return Double(initial) * (1.0 - percent) + Double(next) * (percent)
}


func interpolate(first : Color, second : Color, percent: Double) -> Color {
    let r = linear(initial: first.red, next: second.red, percent: percent)
    let g = linear(initial: first.green, next: second.green, percent: percent)
    let b = linear(initial: first.blue, next: second.blue, percent: percent)
    return rgb(r: UInt(r), g: UInt(g), b: UInt(b))
}

func componentToHex(component : UInt) -> String {
    return String(format:"%02X", component)
}

func colorToHex(color: Color) -> String {
    return [
        "#",
        componentToHex(component: color.red),
        componentToHex(component: color.green),
        componentToHex(component: color.blue)
        ].joined(separator: "")
}

func calculateColorStrings(percentString: String) -> (colorString: String, dropdownString: String, ansiColorString: String) {
    var dropdownString = "\(percentString)%"
    var colorString = ""
    var ansiColor = ""
    
    if let percent = Int(percentString) {
        var interpolationColors : (first: Color, second: Color) = (first: rgb(r: 0,g: 0,b: 0), second: rgb(r: 0,g: 0,b: 0))
        switch(percent) {
        case 0...50: interpolationColors = (first: colors[0], second: colors[1])
        case 50...100: interpolationColors = (first: colors[1], second: colors[2])
        // Catch all to satisfy the compiler
        default: break
        }
        
        switch(percent) {
        case 0...25: ansiColor = "[31m" //red
        case 25...50: ansiColor = "[35m" // magenta
        case 50...75: ansiColor = "[33m" // yellow
        case 75...100: ansiColor = "[32m" // green
        default: break
        }
        
        let percent = percent % 50 == 0 ? 1.0 : Double(percent % 50) / 50.0
        let color = interpolate(first: interpolationColors.first, second: interpolationColors.second, percent: percent)
        colorString = colorToHex(color: color)
        
        
    } else {
        colorString = "#bdc3c7"
        dropdownString = "Not connected"
    }
    return (colorString, dropdownString, ansiColor)
}


func bluetoothDevices() -> String {
    let commandString = "system_profiler SPBluetoothDataType -xml"
    let percentString = shell(args: commandString)
    return percentString
}

func checkYesNoValues(_ text: String) -> Bool {
    
    let yesValue = "attrib_Yes"
    //let noValue = "attrib_No"
    if text == yesValue {
        return true
    } else {
        return false
    }
}


func parseDeviceObject(_ deviceObj: [String:Any] ) -> (c: String, p: String, b: String, cl: String, an: String) {
    
    let deviceConnKey = "device_isconnected"
    let devicePairedKey = "device_ispaired"
    let deviceBatteryKey = "device_batteryPercent"
    
    var connected: String = ""
    var paired: String = ""
    var percentString: String = ""
    
    if let connectValue = deviceObj[deviceConnKey] as? String {
        connected = connectValue
    }
    
    if let pairedValue = deviceObj[devicePairedKey] as? String {
        paired = pairedValue
    }
    
    if let batteryValue = deviceObj[deviceBatteryKey] as? String {
        let batteryStrLevel = batteryValue.substring(to: batteryValue.index(before: batteryValue.endIndex))
        percentString = batteryStrLevel
    }
    
    let (colorString, statusString, ansiColor) = calculateColorStrings(percentString: percentString)
    
    return( connected, paired, statusString, colorString, ansiColor )
}

extension String {
    func chopPrefix(_ count: Int = 1) -> String {
        if self.isEmpty {
            return ""
        }
        return substring(from: index(startIndex, offsetBy: count))
    }
    
    func chopSuffix(_ count: Int = 1) -> String {
        if self.isEmpty {
            return ""
        }
        return substring(to: index(endIndex, offsetBy: -count))
    }
}

func macbookBattery() -> (c: String, s: String, a: String, extra: [String]) {
    
    var extraData = [String]()
    
    let drawPowerCommand = "pmset -g batt | grep 'Now drawing' | awk '{print $4}'"
    let currentPowerCommand = "pmset -g batt | grep 'Internal' | awk '{print $3}'"
    let powerStatusCommand = "pmset -g batt | grep 'Internal' | awk '{print $4}'"
    let powerRemainCommand = "pmset -g batt | grep 'Internal' | awk '{print $5}'"

    let drawPowerString = shell(args: drawPowerCommand).chopPrefix(1)
    let currentPowerString = shell(args: currentPowerCommand).chopSuffix(2)
    let powerStatusString = shell(args: powerStatusCommand).chopSuffix(1)
    let powerRemainString = shell(args: powerRemainCommand)
    
    extraData.append("Now drawing: \(drawPowerString)")
    extraData.append("Status: \(powerStatusString)")
    
    if powerStatusString == "charging" {
        extraData.append("Time until full: \(powerRemainString)")
    } else {
        extraData.append("Time left: \(powerRemainString)")
    }
    
    
    
    let (colorString, dropdownString, ansiColor) = calculateColorStrings(percentString: currentPowerString)
    return (colorString, dropdownString, ansiColor, extraData)
}

var allDevices = [Device]()

func xmlParsing(_ text: String) {
    
    var format = PropertyListSerialization.PropertyListFormat.xml
    
    guard let data = text.data(using: .utf8) else {
        return
    }

    guard let results = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? NSArray else {
        return
    }
    
    for result in results! {
        
        guard let dict = result as? [String:Any] else {
            return
        }
    
        guard let items = dict["_items"] as? NSArray else {
            return
        }
        
        for item in items {
            
            guard let itemDict = item as? [String:Any]  else {
                return
            }
                
            guard let deviceTitles = itemDict["device_title"] as? [[String:Any]] else {
                continue
            }
            
            for deviceTitle in deviceTitles {
                
                if Array(deviceTitle.keys).count > 0 {
                    
                    let deviceName = Array(deviceTitle.keys)[0]
                    
                    guard let deviceObj = deviceTitle[deviceName] as? [String:Any] else {
                        continue
                    }
                    
                    let (connected, paired, statusString, colorString, ansiColor ) = parseDeviceObject(deviceObj)
                    
                    var newDevice = Device()
                    newDevice.ansiColorString = ansiColor
                    newDevice.name = deviceName
                    newDevice.colorString = colorString
                    newDevice.connected = checkYesNoValues(connected)
                    newDevice.paired = checkYesNoValues(paired)
                    newDevice.statusString = statusString
                    
                    if deviceName.characters.count > stringSpacing {
                        stringSpacing = deviceName.characters.count
                    }
                    
                    allDevices.append(newDevice)
                }
            }
        }
    }
}

extension String {
    func padding(length: Int) -> String {
        return self.padding(toLength: length, withPad: " ", startingAt: 0)
    }
}

let (macColorString, macStatus, macAnsiColor, extraData) = macbookBattery()

var macDevice = Device()
macDevice.ansiColorString = macAnsiColor
macDevice.name = "Macbook"
macDevice.colorString = macColorString
macDevice.connected = true
macDevice.paired = true
macDevice.statusString = macStatus
macDevice.extraData = extraData
allDevices.append(macDevice)

var xmlString = bluetoothDevices()
xmlParsing(xmlString)


print("Battery 🔋")
print("---")

for device in allDevices {
    
    let min: Int = 11
    var spacing: Int = 0
    if device.name.characters.count < stringSpacing {
        let diff = stringSpacing - device.name.characters.count
        spacing = diff + min
    } else {
        let diff = device.name.characters.count - stringSpacing
        spacing = diff + min
    }
    
    if device.connected {
        print( "😀 " + device.name + ":".padding(length: spacing) + device.statusString + "| font=Courier color=\(device.colorString)")
    } else {
        print( "😔 " + device.name + ":".padding(length: spacing) + device.statusString + "| font=Courier color=\(device.colorString)")
    }
    
    for data in device.extraData {
        print("--\(data)")
    }
    
}

print("---")
print("Refresh | refresh=true image='iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAMAAAAoLQ9TAAADAFBMVEX///8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAmJiYnJycoKCgpKSkqKiorKyssLCwtLS0uLi4vLy8wMDAxMTEyMjIzMzM0NDQ1NTU2NjY3Nzc4ODg5OTk6Ojo7Ozs8PDw9PT0+Pj4/Pz9AQEBBQUFCQkJDQ0NERERFRUVGRkZHR0dISEhJSUlKSkpLS0tMTExNTU1OTk5PT09QUFBRUVFSUlJTU1NUVFRVVVVWVlZXV1dYWFhZWVlaWlpbW1tcXFxdXV1eXl5fX19gYGBhYWFiYmJjY2NkZGRlZWVmZmZnZ2doaGhpaWlqampra2tsbGxtbW1ubm5vb29wcHBxcXFycnJzc3N0dHR1dXV2dnZ3d3d4eHh5eXl6enp7e3t8fHx9fX1+fn5/f3+AgICBgYGCgoKDg4OEhISFhYWGhoaHh4eIiIiJiYmKioqLi4uMjIyNjY2Ojo6Pj4+QkJCRkZGSkpKTk5OUlJSVlZWWlpaXl5eYmJiZmZmampqbm5ucnJydnZ2enp6fn5+goKChoaGioqKjo6OkpKSlpaWmpqanp6eoqKipqamqqqqrq6usrKytra2urq6vr6+wsLCxsbGysrKzs7O0tLS1tbW2tra3t7e4uLi5ubm6urq7u7u8vLy9vb2+vr6/v7/AwMDBwcHCwsLDw8PExMTFxcXGxsbHx8fIyMjJycnKysrLy8vMzMzNzc3Ozs7Pz8/Q0NDR0dHS0tLT09PU1NTV1dXW1tbX19fY2NjZ2dna2trb29vc3Nzd3d3e3t7f39/g4ODh4eHi4uLj4+Pk5OTl5eXm5ubn5+fo6Ojp6enq6urr6+vs7Ozt7e3u7u7v7+/w8PDx8fHy8vLz8/P09PT19fX29vb39/f4+Pj5+fn6+vr7+/v8/Pz9/f3+/v7///87ptqzAAAAJXRSTlMAgA5ABAHjYRLswnooVM0CyLDK2mCpIMSvX5AFm5SRscBeH2Kql1edqgAAAGdJREFUeJyNjUcSgCAUQ1GKSlGw9879r6j4Wbogm0zeTBKEgkQSnrFmQBhDTstcyLbu+jH6cqENdT7NFoCq4s+t9QDFYU+/8t3oXYNcKQ8W4pwaXQBYt/04pcjLFCoY0+tmGU9I2NMDXoEEmA7BEvIAAAAASUVORK5CYII='")

