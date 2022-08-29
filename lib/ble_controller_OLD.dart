import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:flutter_blue/gen/flutterblue.pb.dart' as proto;

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'dialogs.dart';
import 'package:intl/intl.dart';
import 'package:cbor/simple.dart';
import 'package:byte_flow/byte_flow.dart';




class BleControllerOld extends GetxController {
  late GetStorage _myLocalStorage;

  FlutterBlue flutterBlue = FlutterBlue.instance;
  var isBluetoothOn = false.obs;

  var macAddressFromQR = "----".obs;  // Getting from QR code
  var _macFoundByQRCode = false;
  get macFound => _macFoundByQRCode;

  var devices = <BluetoothDevice>[].obs;
  late final activeDevice = Rxn<BluetoothDevice>();

  String? lastConnectedDeviceID;  // to resume a previous connection after opening the app
  var resumeLastConnection = true.obs;


  static Map<String, String> iosMacAddressMapper = {}; // Mapping an iOS UUID and a BLE's MacAddress

  bool isScanning = false;
  var isConnecting = false.obs;
  var isLoading = false.obs;
  var connected = false.obs;

  int messageSize = 0;
  List<int> dataChunksCollector = [];

  List<BluetoothService> bluetoothServices = [];
  BluetoothService? serviceOne;
  BluetoothService? serviceTwo;  /// for CBOR exchange

  var batteryValue = Rxn<String>();
  var tempValue = Rxn<String>();
  var stepsValue = Rxn<String>();
  var locationValue = Rxn<String>();
  var accelerometerValue = Rxn<String>();
  var networkValue = Rxn<String>();
  var buttonValue = Rxn<String>();
  var buttonLog = ''.obs;
  var fallDetectionCount = Rxn<String>();
  var fallEvent = false.obs;
  int fallsDetected = 0;
  var imeiValue = Rxn<String>();
  var iccidValue= Rxn<String>();





  BluetoothCharacteristic? batteryChar;
  BluetoothCharacteristic? tempChar;
  BluetoothCharacteristic? stepsChar;
  BluetoothCharacteristic? locationChar;
  BluetoothCharacteristic? accelerometerChar;
  BluetoothCharacteristic? networkChar;
  BluetoothCharacteristic? buttonChar;
  BluetoothCharacteristic? imeiChar;
  BluetoothCharacteristic? iccidChar;
  BluetoothCharacteristic? activationIdChar;
  BluetoothCharacteristic? configChar;
  BluetoothCharacteristic? timestampChar;
  BluetoothCharacteristic? watchChar;
  BluetoothCharacteristic? firstChar;   // write message length
  BluetoothCharacteristic? secondChar; // send actual payload e.i. cborConfig
  BluetoothCharacteristic? thirdChar; // commands



  StreamSubscription? batteryNotifier;
  StreamSubscription? tempNotifier;
  StreamSubscription? stepsNotifier;
  StreamSubscription? locationNotifier;
  StreamSubscription? accelerometerNotifier;
  StreamSubscription? networkNotifier;
  StreamSubscription? buttonNotifier;
  StreamSubscription? firstNotifier;
  StreamSubscription? secondNotifier;
  StreamSubscription? thirdNotifier;




  // @override
  // void onInit() {
  //   _myLocalStorage = GetStorage();
  //   ever(resumeLastConnection, (value) => _myLocalStorage.write('resumeLastConnection', value));
  //
  //   isBluetoothTurnedOn();
  //
  //   lastConnectedDeviceID = _myLocalStorage.read('lastConnectedDeviceID');
  //   resumeLastConnection.value = _myLocalStorage.read('resumeLastConnection') ?? false;
  // }


  Future<void> isBluetoothTurnedOn () async {
    flutterBlue.state.listen((state) {
      print("############ BL State: ${state.toString()}");
      if (state == BluetoothState.on) {
        isBluetoothOn.value = true;
      } else {
        isBluetoothOn.value = false;
      }
    });
  }


  Future<void> resumePreviousConnection() async {
    if (resumeLastConnection.value) {
      lastConnectedDeviceID = _myLocalStorage.read('lastConnectedDeviceID');
      print("######## lastConnectedDeviceID $lastConnectedDeviceID");
      if (lastConnectedDeviceID != null) {
        await scanDevices();
        MyDialogs.info("Resuming a previous connection...", "Last connected device: ${iosMacAddressMapper[lastConnectedDeviceID] ?? lastConnectedDeviceID}", seconds: 5, position: "BOTTOM", icon: Icon(Icons.bluetooth, color: Colors.white));
        await Future.delayed(Duration(seconds: 1));
        print("iosMacAddressMap $iosMacAddressMapper");
        for (BluetoothDevice device in devices){ //Todo iOS
          if(device.id.id == lastConnectedDeviceID){
            setActiveDevice(device);
            await connectToDevice();
            return;
          }
        }
        print("an available device with the lastConnectedDeviceID $lastConnectedDeviceID isn't found");
        MyDialogs.error("Unable to resume a connection!", "The device with ${iosMacAddressMapper[lastConnectedDeviceID] ?? lastConnectedDeviceID} isn't available", seconds: 10, position: "BOTTOM");
      }
    }
  }


  BluetoothDevice toBluetoothDevice(String name, String MacAddress) {
    proto.BluetoothDevice p = proto.BluetoothDevice.create();

    p.name = name;
    p.type = proto.BluetoothDevice_Type.LE;
    p.remoteId = MacAddress;

    return BluetoothDevice.fromProto(p);
  }


  Future<void> scanDevices() async {
    isScanning = await flutterBlue.isScanning.first;
    print(isScanning);

    if (isScanning){
      await flutterBlue.stopScan();
    }

    // Start scanning
    flutterBlue.startScan(timeout: Duration(seconds: 4));
    print("start scanning...");

    print("resetting devices and _macFoundByQRCode...");
    activeDevice.value = null; //reset
    _macFoundByQRCode = false; // reset
    devices.value = []; //reset
    devices.refresh();


    var subscription = flutterBlue.scanResults.listen((results) {
      for (ScanResult scanResult in results) {
        // BluetoothDevice? device;
        if (scanResult.device.name == "Seabird") {
          String extractedMacAddress = _extractMacAddressFromManufacurerData(scanResult.advertisementData.manufacturerData);
          // device = toBluetoothDevice("Seabird", scanResult.device.id.toString() ); //re-creating the BluetoothDevice object
          iosMacAddressMapper[scanResult.device.id.id] = extractedMacAddress.isNotEmpty ? extractedMacAddress : scanResult.device.id.id;  // {UUID or MacAddress : MacAddress}
          addDevice(scanResult.device);
        }


        if (iosMacAddressMapper[scanResult.device.id.id] == macAddressFromQR.value) {
          print("#### Found a device with MAC Address ${scanResult.device.id.toString()} // ${macAddressFromQR.value}");
          _macFoundByQRCode = true;
          print("### _macFound $_macFoundByQRCode");
          if(activeDevice.value?.id.toString() != macAddressFromQR.value) {
            setActiveDevice(scanResult.device);
            flutterBlue.stopScan();
          }
        }
      }
    });


    print(iosMacAddressMapper);
    await flutterBlue.stopScan();
    print("stop scanning");

    // await flutterBlue.stopScan();
  }


  // Workaround for IOS
  // (ex. we have to extract 'c4:c4:0b:dc:b8:22' from {47138: [220, 11, 196, 196]})
  String _extractMacAddressFromManufacurerData(Map<int, List<int>> manufacturerData) {
    String bleAddr = "";

    if (manufacturerData.keys != null && manufacturerData.keys.isNotEmpty) {
      var key = manufacturerData.keys.first;
      // print(key);
      List<int> chunks = []; // expected result ex. [196, 196, 11, 220, 47, 38]
      if(manufacturerData[key] != null) {
        chunks.addAll(manufacturerData[key]!.reversed);
        chunks.addAll(writeInt16(key).reversed);
      }

      for (int i=0; i < chunks.length; i++) {
        var hex = chunks[i].toRadixString(16).padLeft(2, "0"); // ex. c4
        if(i == chunks.length || i == 0) {
          bleAddr = bleAddr + hex;
        } else {
          bleAddr = bleAddr + ":" + hex;
        }
      }
    }
    return bleAddr.toUpperCase();
  }


  Future<void> _stopScanning() async {
    var isScanning = await flutterBlue.isScanning.first;

    if (isScanning) {
      print("_stopScanning");
      await flutterBlue.stopScan();
      print("_stopScanning DONE");
      await Future.delayed(new Duration(milliseconds: 1000));
    } else {
      print("_stopScanning. NOT SCANNING! Continue");
    }
  }



  void addDevice(BluetoothDevice device) {
    if (device.name.contains("Seabird")) {
      if (!devices.contains(device)) {
        print("Add SeaBird device: ${device.id} ${device.name}");
        devices.add(device);
        devices.refresh();
      } else {
        // print("SeaBird device already found: ${device.id} ${device.name}");
      }
    }
  }

  void setActiveDevice(BluetoothDevice device) {
    print("set active BLE device: ${iosMacAddressMapper[device.id] ?? device.id}");
    // print("set active BLE device: ${device.id ?? "<null>"}");
    activeDevice.value = device;
  }


  Future<void> connectToDevice() async {
    isConnecting.value = true;
    connected.value = false;
    print("connectToDevice connected: ${connected.value} _devices.length = ${devices.length}");
    await Future.delayed(const Duration(seconds: 1));
    // if (!connected.value) {
    if (devices.isNotEmpty && activeDevice.value != null) {
        print("_deinitCharacteristics");
        _deinitCharacteristics();
        print("_deinitValues");
        _deinitValues();
        print("await _stopScanning();");
        await _stopScanning();
        try {
          print("connecting to id: ${activeDevice.value?.id ?? "null"} name: ${activeDevice.value?.name ?? "null"}");
          print("#### START await activeDevice.value?.connect(); ${activeDevice.value!.id.id}"); // TODO:REMOVE
          await activeDevice.value!.connect(autoConnect: true).then((data) {
                print("#### END await activeDevice.value?.connect();"); // TODO:REMOVE
                connected.value = true;
                // isConnecting.value = false;
                print("Saving a lastConnectedDeviceID ${activeDevice.value!.id} into local storage");
                _myLocalStorage.write('lastConnectedDeviceID', activeDevice.value!.id.id);
                // MyDialogs.success("You're now connected to", "the device ${iosMacAddressMap[activeDevice.value?.id.id]}", seconds: 6, icon: Icon(Icons.bluetooth, color: Colors.white));
            }).onError((error, stackTrace) => null)
            .timeout(Duration(seconds: 15), onTimeout: () {
                MyDialogs.error("TIMEOUT", "e.toString()");
                connected.value = false;
                isConnecting.value = false;
            });

        } on Exception catch (e) {
            print("Connection error: " + e.toString());
            // if (e.code != "already connected") {
            //   throw e;
            // }
        } finally {
          if (connected.value) {
            print("Start service discovery");
            bluetoothServices = (await activeDevice.value!.discoverServices());
            for (BluetoothService service in bluetoothServices) {
              if (service.uuid.toString() == "6da295a0-67e6-11ec-90d6-0242ac120003") {
                serviceOne = service;
              } else if (service.uuid.toString() == "6da295a0-67e6-11ec-90d6-0242ac120004") {
                serviceTwo = service;
              }
            }
            for (BluetoothCharacteristic characteristic in serviceOne!.characteristics) {
              print("test char ${characteristic.uuid.toString()}");
              switch (characteristic.uuid.toString()) {
              //   case "6da295a1-67e6-11ec-90d6-0242ac120003":
              //     batteryChar = characteristic;
              //     print("FOUND ${characteristic.uuid.toString()} BATTERY");
              //     await _getBattery();
              //     break;
              // case "6da295a2-67e6-11ec-90d6-0242ac120003":
              //   tempChar = characteristic;
              //   print("FOUND ${characteristic.uuid.toString()} TEMP");
              //   await _getTempData();
              //   break;
              // case "6da295a3-67e6-11ec-90d6-0242ac120003":
              //   stepsChar = characteristic;
              //   print("FOUND ${characteristic.uuid.toString()} STEPS");
              //   await _getSteps();
              //   break;
              // case "6da295a4-67e6-11ec-90d6-0242ac120003":
              //   locationChar = characteristic;
              //   print("FOUND ${characteristic.uuid.toString()} LOCATION");
              //   await _getLocation();
              //   break;
              // case "6da295a5-67e6-11ec-90d6-0242ac120003":
              //   accelerometerChar = characteristic;
              //   print("FOUND ${characteristic.uuid.toString()} ACCELEROMETER");
              //   await _getAccelerometer();
              //   break;
              // case "6da295a6-67e6-11ec-90d6-0242ac120003":
              //   networkChar = characteristic;
              //   print("FOUND ${characteristic.uuid.toString()} NETWORK");
              //   await _getNetwork();
              //   break;
              // case "6da295a7-67e6-11ec-90d6-0242ac120003":
              //   buttonChar = characteristic;
              //   print("FOUND ${characteristic.uuid.toString()} BUTTON");
              //   await _getButton();
              //   break;
              case "6da295a8-67e6-11ec-90d6-0242ac120003":
                imeiChar = characteristic;
                print("FOUND ${characteristic.uuid.toString()} IMEI");
                await _getImei();
                break;

              case "6da295ab-67e6-11ec-90d6-0242ac120003":
                iccidChar = characteristic;
                print("FOUND ${characteristic.uuid.toString()} ICCID");
                await _getIccid();
                break;

              case "6da295a9-67e6-11ec-90d6-0242ac120003":
                watchChar = characteristic;
                print("FOUND ${characteristic.uuid.toString()} Watch Char");
                break;

              case "6da295aa-67e6-11ec-90d6-0242ac120003":
                timestampChar = characteristic;
                print("FOUND ${characteristic.uuid.toString()} Timestamp Char");
                var ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
                await timestampChar!.write(writeInt32(ts));
                break;
              default:
                print("Unknown Characteristic ${characteristic.uuid.toString()}");
              }
            }

            for (BluetoothCharacteristic characteristic in serviceTwo!.characteristics) {
              // print("test char ${characteristic.uuid.toString()}");
              switch (characteristic.uuid.toString()) {
                case "6da295a1-67e6-11ec-90d6-0242ac120004": // UDP Payload
                  firstChar = characteristic;
                  print("FOUND ${characteristic.uuid.toString()} firstChar");
                  await _readData();
                  break;

                case "6da295a2-67e6-11ec-90d6-0242ac120004": // Message Size
                  secondChar = characteristic;
                  print("FOUND ${characteristic.uuid.toString()} secondChar");
                  await _checkDataSizeAndSend();
                  break;

                case "6da295a3-67e6-11ec-90d6-0242ac120004": // commands (16 - means ble transmitting 'data' package, write[17] - we're sending cbor conf, write[16] - we're sending udp response back to Ble )
                  thirdChar = characteristic;
                  print("FOUND ${characteristic.uuid.toString()} thirdChar");
                  await _getCommand();
                  break;
                default:
                  print("Unknown Characteristic ${characteristic.uuid.toString()}");
              }
            }

            if (_characteristicsFound()) {
              _readCharacteristic();
            } else {
              print("Not all characteristics found!");
            }
            isConnecting.value = false;
        }
        }
      }
    // }
    isConnecting.value = false;
    // refresh();
  }

  Future<void> disconnectDevice() async {
    try {
      print("disconnect from ${activeDevice.value?.id ?? "null"} ${activeDevice.value?.name ?? "null"}");
      _deinitCharacteristics();
      _deinitValues();
      await _cancelSubscribers();
      await activeDevice.value?.disconnect();
      connected.value = false;
    } catch(e) {
      print("error while disconnecting: $e}");
    }
  }

  Future<void> _getCommand() async {
    if(thirdChar != null) {
      // await thirdChar!.setNotifyValue(false);
      await Future.delayed(Duration(milliseconds: 500));
      await thirdChar!.setNotifyValue(true);

      thirdNotifier = thirdChar!.value.listen((value) {
        print("Command: $value");
        if(value.isNotEmpty){
          if(value[0] == 16) {
            // _checkMessageSizeAndSendUdpData()
            // isAwaitingUdp = true;
          }
        }
      });
    }
  }

  Future<void> _readData() async {
    await Future.delayed(Duration(milliseconds: 500));
    if (firstChar != null) {
      await firstChar!.setNotifyValue(true);
      print("_readData - firstChar!.setNotifyValue(true)");
      firstNotifier = firstChar!.value.listen((value) {
        if(value.isNotEmpty){
          print("Receiving chunk: $value");
          dataChunksCollector.addAll(value);
        }
      });
    }
  }


  // if transmitted data size is correct: 1. redirect data through udp socket, 2. transmit back the udp response and 3. send phone location through http
  Future<void> _checkDataSizeAndSend() async {

    // bool isConnectedDeviceMine = Get.find<BTDeviceController>().myDevices.value.where((element) => element.bleAddr == iosMacAddressMapper[activeDevice.value?.id.id]).toList().isNotEmpty;
    // print("--- isConnectedDeviceMine $isConnectedDeviceMine");


    if (secondChar != null) {
      await secondChar!.setNotifyValue(true);
      secondNotifier = secondChar!.value.listen((value) {
        print("Length: $value");
        if (value.isNotEmpty && value.length == 2) {
          var size = value[0] + (value[1] << 8);
          if(size > 0) {
            messageSize = size;
            print("messageSize $messageSize");
          }

          if(size == 0) { //receiving finished, send collected data to the backend
            print("Size is 0, receiving has finished");
            if (dataChunksCollector.length == messageSize) {
              print("dataChunksCollector length and message size are equal");
              // print(dataChunksCollector);

              // todo isAwaitingUdp
              sendToBackendUsingUdpSocket(dataChunksCollector).then((udpResponse) async {
                print("response from UDP  $udpResponse");
                // send command-16 before transmitting the UDP response
                await thirdChar!.write([16]);
                // Transmit
                await transmitToBle(udpResponse);

                // get location from phone
                // Gps currentGps = await GeoLocationApi.getCurrentLocation();

                // update location Http call
                // if(isConnectedDeviceMine) {
                //   await _sendPhoneLocationToPlatform(currentGps);
                // } else {
                //   print("we ar not sending a phone location, since device doesn't belong to the current user");
                // }
              });

              dataChunksCollector = [];
            }
            }
        }

        });
    }
  }

  // UDP SOCKET
  Future<List<dynamic>> sendToBackendUsingUdpSocket(List<int> message) async {
    List<dynamic> response = [];
    int port = 1337;
    InternetAddress destination = InternetAddress("137.135.160.14");
    RawDatagramSocket udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    udp.listen((e) {
      Datagram? datagram = udp.receive();
      if (datagram != null) {
        response.addAll(datagram.data);
      }
    });
    var res = udp.send(message, destination, port);
    print("sent size (to UDP Socket) $res");
    await Future.delayed(Duration(seconds: 5));
    udp.close();
    return response;
  }


  // Future<void> _sendPhoneLocationToPlatform(Gps gps) async {
  //   try {
  //     final macAddress = iosMacAddressMapper[activeDevice.value!.id.id]; // Todo iosMap
  //
  //     var activationId = Get.find<BTDeviceController>().getActivationIDByMacAddress(macAddress); // Todo: modify endpoint, send only imei
  //     var imei         = Get.find<BTDeviceController>().getImeiByMacAddress(macAddress);
  //     int ts           = DateTime.now().millisecondsSinceEpoch;
  //
  //     if(activationId != null && imei !=null) {
  //       print(" -------- ## GPS ACCURACY ${gps.acc}");
  //       // if(gps.acc < 30.0) {
  //         print("_sendCurrentLocationToPlatform() ${gps.toString()}");
  //         await GeoLocationApi.sendLocation(activationId, imei, ts, gps);
  //       // } else {
  //       //   print("--- We aren't sending a location from phone since it isn't an accurate. acc: ${gps.acc}");
  //       // }
  //     } else {
  //       print("--- We aren't able to send a location from the phone since either activationId/imei is null for current device or currentDevice has not been set");
  //     }
  //
  //   } on CustomException catch (e) {
  //     print(e);
  //     // MyDialogs.error("ERROR", e.msg);
  //   } on Exception catch (e) {
  //     print(e);
  //     // MyDialogs.error("ERROR", e.toString());
  //   }
  // }

  // ex. static CONFIGURATIONS.cborFullPlanConfig
  Future<void> applyCborConfiguration (Map cborConfigMap) async {
    try{
      isLoading.value = true;
      print("CborConfigMap: ${cborConfigMap}");

      final List<int> encoded = cbor.encode(cborConfigMap);

      // send command-17 before transmitting the Cbor data
      print("sending command[17] before transmitting the Cbor data");
      await thirdChar!.write([17]);

      await transmitToBle(encoded);

    } on Exception catch(e) {
      print(e.toString());

    } finally {
      isLoading.value= false;
    }
  }


  // Split the data into 20 bytes chunk
  // and transmit one by one to the BLE
  Future<void> transmitToBle(List<dynamic> data) async {
    // inform ble device about the size of upcoming data (int16)
    List<int> size = writeInt16(data.length);
    print("${data.length} bytes have to be transmitted $size");
    await firstChar!.write(size);

    List<dynamic> chunks = chunk(data, 20); // Returns ['1', '2'],['3', '4']  // byte_flow package
    for (var chunk in chunks) {
      print("Transmitting chunk: ${chunk}");
      List<int> ch = List<int>.from(chunk); //convert dynamic to List<int>
      await secondChar!.write(ch); // Todo: add try catch exception
    }

    // await Future.delayed(Duration(seconds: 1));
    // Send 0 to inform sending of the payload is completed
    await firstChar!.write(writeInt16(0));
    print("Transmission has finished ${writeInt16(0)}");
  }


  /// manual alignment of watch hands
  Future<void> increaseWatchHour() async {
    if(watchChar != null){
      print("increaseWatchHour watchChar!.write([1]");
      await watchChar!.write([0x01]); //1
    }
  }

  Future<void> increaseWatchMinute() async {
    if(watchChar != null){
      print("increaseWatchMinute watchChar!.write([1]");
      await watchChar!.write([0x10]); //16
    }
  }


  void _parseBattery(List<int> value) {
    print("parse battery $value");

    if (value.length >= 2) {
      batteryValue.value = _batteryLevel(value);
      print("battery: $batteryValue [${batteryChar!.uuid}]");
    }
  }

  String _batteryLevel(List<int> values) {
    var volts = (values[0] + (values[1] << 8)) * 0.001;
    if (volts < 3.5) {
      return "LOW";
    } else if (3.5 < volts && volts < 3.8) {
      return "MEDIUM";
    } else if (volts > 3.8) {
      return "HIGH";
    } else {
      return "Incorrect battery voltage";
    }
  }



  Future<void> _getImei() async {
    imeiValue.value = null;
    List<int> imeiBytes = await imeiChar!.read();
    print("### parse IMEI  $imeiBytes");
    imeiValue.value = utf8.decode(imeiBytes);
    print("imei: ${imeiValue.value} [${imeiChar?.uuid}]");
  }

  Future<void> _getIccid() async {
    iccidValue.value = null;
    List<int> iccidBytes = await iccidChar!.read();
    print("### parse ICCID  $iccidBytes");

    List<int> iccidBytesWithoutZeroes = iccidBytes.sublist(0, iccidBytes.indexOf(0));  /// removing trailing zeroes
    iccidValue.value = utf8.decode(iccidBytesWithoutZeroes);
    print("ICCID: ${iccidValue.value} [${iccidChar?.uuid}]");
  }

  Future<void> _getTempData() async {
    await tempChar!.setNotifyValue(true);
    tempNotifier = tempChar!.value.listen((value) {
      _parseTemp(value);
    });
  }

  void _parseTemp(List<int> value) {
    print("parse temp $value");
    if (value.length >= 4) {
      var temp = _readInt32(value, 0) / 100;
      tempValue.value = "${temp.toStringAsFixed(1)}°C";
      print("temp: $tempValue [${tempChar?.uuid}]");
    }
  }

  Future<void> _getSteps() async {
    await stepsChar!.setNotifyValue(true);
    stepsNotifier = stepsChar!.value.listen((value) {
      _parseSteps(value);
    });
  }

  void _parseSteps(List<int> value) {
    print("parse steps $value");
    if (value.length >= 4) {
      var steps =
      (value[0] + (value[1] << 8) + (value[2] << 16) + (value[3] << 24));
      stepsValue.value = "${steps.toStringAsFixed(1)} steps";
      print("steps: $stepsValue [${stepsChar?.uuid}]");
    }
  }

  Future<void> _getLocation() async {
    await locationChar!.setNotifyValue(true);
    locationNotifier = locationChar!.value.listen((value) {
      _parseLocation(value);
    });
  }

  void _parseLocation(List<int> value) {
    print("parse location $value");

    if (value.length >= 8) {
      var lat = _readInt32(value, 0) / 100000;
      var lng = _readInt32(value, 4) / 100000;
      locationValue.value = "$lat, $lng";
      print("location: $locationValue [${locationChar?.uuid}]");
    }
  }


  Future<void> _getBattery() async {
    await batteryChar!.setNotifyValue(true);
    batteryNotifier = batteryChar!.value.listen(
        _parseBattery
    );
  }

  Future<void> _getAccelerometer() async {
    await accelerometerChar!.setNotifyValue(true);
    accelerometerNotifier = accelerometerChar!.value.listen((value) {
      _parseAccelerometer(value);
    });
  }

  void _parseAccelerometer(List<int> value) {
    print("parse accelerometer $value");
    if (value.length >= 6) {
      var accX = (_readInt16(value, 0) / 100).toStringAsFixed(2);
      var accY = (_readInt16(value, 2) / 100).toStringAsFixed(2);
      var accZ = (_readInt16(value, 4) / 100).toStringAsFixed(2);


      // var accFall = value[6];
      // if (accFall > 0) {
      //   fallEvent = true;
      //   fallsDetected++;
      //   fallDetectionCount = "Falls: $fallsDetected";
      // }


      accelerometerValue.value = "x: $accX, y: $accY, z: $accZ";
      print("accelerometerValue: $accelerometerValue [${accelerometerChar?.uuid}]");
    }
  }

  Future<void> _getNetwork() async {
    await networkChar!.setNotifyValue(true);
    networkNotifier = networkChar!.value.listen((value) {
      _parseNetwork(value);
    });
  }

  void _parseNetwork(List<int> value) {
    print("parse network $value");
    if (value.length >= 1) {
      var attached = value[0];
      networkValue.value = attached == 0 ? "Disconnected" : "Connected";
      print("network char received: $networkValue [${networkChar?.uuid}]");
    }
  }

  Future<void> _getButton() async {
    await buttonChar!.setNotifyValue(true);
    buttonNotifier = buttonChar!.value.listen((value) {
      _parseButton(value);
    });
  }

  void _switchEventInfoHelper(int buttonEventInfo, String action){
    switch(buttonEventInfo) {
      case 0: buttonValue.value = "Idle alarm is " + action; break;   // example [7, 0]
      case 1: buttonValue.value = "Beacon alarm is " + action; break;
      case 2: buttonValue.value = "Button alarm is " + action; break;
      case 3: buttonValue.value = "Fall alarm is " + action; break;
      case 4: buttonValue.value = "Flip alarm is " + action; break;
      case 5: buttonValue.value = "Battery alarm is " + action; break;
      case 6: buttonValue.value = "Temperature alarm is " + action; break;
      case 7: buttonValue.value = "Geofence alarm is " + action;; break;
    }
  }

  // first byte is an event type, second is additional info (e.g. alarm type).
  void _parseButton(List<int> value) {
    print("parse button $value");
    if (value.length >= 1) {
      var buttonEventType = value[0];   // alarmEventType
      var buttonEventInfo = value[1];   // alarmEventInfo

      switch(buttonEventType) {
        case 0: buttonValue.value = "Button pressed"; break;

        case 1: buttonValue.value = "heartbeat sending"; break;
        case 2: buttonValue.value = "heartbeat failure"; break;
        case 3: buttonValue.value = "heartbeat success"; break;

        case 4: buttonValue.value = "data sending"; break;
        case 5: buttonValue.value = "data failure"; break;
        case 6: buttonValue.value = "data success"; break;

        case 7:
          switch(buttonEventInfo) {
            case 0: buttonValue.value = "Idle alarm is set"; break;   // example [7, 0]
            case 1: buttonValue.value = "Beacon alarm is set"; break;
            case 2: buttonValue.value = "Button alarm is set "; break;
            case 3:
              buttonValue.value = "Fall alarm is set";

              fallEvent.value = true;
              fallsDetected++;
              fallDetectionCount.value = "Falls: $fallsDetected";
              break;
            case 4: buttonValue.value = "Flip alarm is set"; break;
            case 5: buttonValue.value = "Battery alarm is set"; break;
            case 6: buttonValue.value = "Temperature alarm is set"; break;
            case 7: buttonValue.value = "Geofence alarm is set"; break;
          } break;

        case 8: _switchEventInfoHelper(buttonEventInfo, "sending"); break;
        case 9: _switchEventInfoHelper(buttonEventInfo, "failure"); break;
        case 10: _switchEventInfoHelper(buttonEventInfo, "success"); break;

        case 11: buttonValue.value = "audio recording started"; break;
        case 12: buttonValue.value = "audio recording stopped"; break;
        case 13: buttonValue.value = "audio sending"; break;
        case 14: buttonValue.value = "audio failure"; break;
        case 15: buttonValue.value = "audio success"; break;
        case 16: buttonValue.value = "modem went to sleep"; break;
      }

      if(buttonValue.value != null) {
        appendButtonLog(buttonValue.value!);
      }

      print("button char received: $buttonValue [${buttonChar?.uuid}]");
    }
  }


  Future<void> _cancelSubscribers() async {
    await tempNotifier?.cancel();
    await batteryNotifier?.cancel();
    await stepsNotifier?.cancel();
    await locationNotifier?.cancel();
    await accelerometerNotifier?.cancel();
    await buttonNotifier?.cancel();
    await networkNotifier?.cancel();
  }

  void appendButtonLog(String buttonValue) {
    var log = DateFormat("HH:mm:ss").format(DateTime.now()) + ": " + buttonValue;
    var logCpy = buttonLog;
    if (logCpy == null) {
      logCpy.value = log;
    } else {
      var lines = logCpy.split("\n");

      logCpy.value = log;

      var nrOfLines = lines.length > 9 ? 9 : lines.length;
      for(int i = 0; i < nrOfLines; i++) {
        logCpy.value += "\n" + lines[i];
      }
    }

    buttonLog = logCpy;
  }

  int _readInt16(List<int> value, int i) {
    int unsignedValue = value[i] + (value[i+1] << 8);
    if (unsignedValue < 0x8000) {
      return unsignedValue;
    } else {
      return unsignedValue - 0x10000;
    }
  }

  int _readInt32(List<int> value, int i) {
    int unsignedValue =
        value[i] +
            (value[i + 1] << 8) +
            (value[i + 2] << 16) +
            (value[i + 3] << 24);

    if (unsignedValue < 0x80000000) {
      return unsignedValue;
    } else {
      return unsignedValue - 0x100000000;
    }
  }

  List<int> writeInt16(int value) {
    final list = <int>[];
    for (int i = 0; i < 2; i++) {
      list.add((value >> i * 8) & 0xFF);
    }
    return list;
  }

  List<int> writeInt32(int value) {
    final list = <int>[];
    for (int i = 0; i < 4; i++) {
      list.add((value >> i * 8) & 0xFF);
    }
    return list;
  }

  // // Convert int16 to 2 bytes. ex. 23 -> [23, 0]
  // Uint8List getListOfBytesFromInt16(int value) {
  //   return Uint8List(2)..buffer.asInt16List()[0] = value;
  // }
  //
  // // Convert int32 to 4 bytes. ex. 23 -> [23, 0, 0, 0]
  // Uint8List getListOfBytesFromInt32(int value) {
  //   return Uint8List(4)..buffer.asInt32List()[0] = value;
  // }

  Future<void> stopScanning() async {
    isScanning = false;
    await _stopScanning();
  }

  void _deinitCharacteristics() {
    batteryChar = null;
    tempChar = null;
    stepsChar = null;
    locationChar = null;
    accelerometerChar = null;
    networkChar = null;
    buttonChar = null;
    imeiChar = null;
    timestampChar = null;
    watchChar = null;
  }

  void _deinitValues() {
    if (this.tempValue.value != null) this.tempValue.value = null;
    if (this.batteryValue.value != null) this.batteryValue.value = null;
    if (this.stepsValue.value != null) this.stepsValue.value = null;
    if (this.locationValue.value != null) this.locationValue.value = null;
    if (this.accelerometerValue.value != null) this.accelerometerValue.value = null;
    if (this.networkValue.value != null) this.networkValue.value = null;
    if (this.buttonValue.value != null) this.buttonValue.value = null;
    if (this.buttonLog.value != null) this.buttonLog.value = "";
    if (this.fallDetectionCount.value != null) this.fallDetectionCount.value = null;
    if (this.imeiValue.value != null) this.imeiValue.value = null;
    if (this.iccidValue.value != null) this.iccidValue.value = null;
    refresh();
  }

  bool _characteristicsFound() {
    return batteryChar != null &&
        tempChar != null &&
        stepsChar != null &&
        locationChar != null &&
        accelerometerChar != null &&
        networkChar != null &&
        imeiChar != null &&
        iccidChar != null &&
        buttonChar != null;
  }

  Future<void> _readCharacteristic() async {
    print("Reading characteristics!");
    _parseBattery(await batteryChar!.read());
    _parseTemp(await tempChar!.read());
    _parseSteps(await stepsChar!.read());
    _parseLocation(await locationChar!.read());
    _parseAccelerometer(await accelerometerChar!.read());
    _parseNetwork(await networkChar!.read());
    _parseButton(await buttonChar!.read());
    print("Done reading characteristics");
  }







}