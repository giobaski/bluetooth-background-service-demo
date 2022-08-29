import 'package:flutter/material.dart';
import 'package:get/get.dart';

class MyDialogs {

static SnackbarController error(String title, String subTitle, {int seconds = 5, String position = "TOP", Icon icon = const Icon(Icons.error, color: Colors.white)}) {
  return Get.snackbar(
      title,
      subTitle,
      colorText: Colors.white,
      // showProgressIndicator: true,
      // progressIndicatorBackgroundColor: Colors.red,
      icon: icon,
      backgroundColor: Colors.red.withOpacity(0.9),
      duration: Duration(seconds: seconds),
      margin: EdgeInsets.all(0),
      borderRadius: 1,
      forwardAnimationCurve: Curves.easeIn,
      reverseAnimationCurve: Curves.easeInOut,
      snackPosition: position == "TOP"? SnackPosition.TOP : SnackPosition.BOTTOM);
}

static SnackbarController success(String title, String subTitle, {int seconds = 3, String position = "TOP", Icon icon = const Icon(Icons.check_circle, color: Colors.white)}) {
    return Get.snackbar(
        title,
        subTitle,
        colorText: Colors.white,
        // showProgressIndicator: true,
        // progressIndicatorBackgroundColor: Colors.green,
        icon: icon,
        backgroundColor: Colors.green,
        duration: Duration(seconds: seconds),
        margin: EdgeInsets.all(0),
        borderRadius: 1,
        forwardAnimationCurve: Curves.easeIn,
        reverseAnimationCurve: Curves.easeInOut,
        snackPosition: position == "TOP"? SnackPosition.TOP : SnackPosition.BOTTOM);
}

static SnackbarController info(String title, String subTitle, {int seconds = 5, String position = "TOP",  Icon icon = const Icon(Icons.info, color: Colors.white)}) {
  return Get.snackbar(
      title,
      subTitle,
      colorText: Colors.black,
      // showProgressIndicator: true,
      // progressIndicatorBackgroundColor: Colors.red,
      icon: icon,
      backgroundColor: Colors.grey,
      duration: Duration(seconds: seconds),
      margin: EdgeInsets.all(0),
      borderRadius: 1,
      forwardAnimationCurve: Curves.easeIn,
      reverseAnimationCurve: Curves.easeInOut,
      snackPosition: position == "TOP"? SnackPosition.TOP : SnackPosition.BOTTOM);
}


}