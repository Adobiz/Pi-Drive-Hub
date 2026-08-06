/// PI 网盘品牌徽标：原云朵图标 + 中间叠加 π 数学符号。
///
/// 保留云朵 logo 本体，仅在中心叠加 π，用作登录页与应用内标题栏图标。
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';

class PiLogo extends StatelessWidget {
  /// 徽标边长（正方形），默认 64
  final double size;

  /// π 符号颜色，默认品牌蓝
  final Color piColor;

  /// 云朵图标颜色，默认品牌蓝
  final Color cloudColor;

  const PiLogo({
    super.key,
    this.size = 64,
    this.piColor = kBrandColor,
    this.cloudColor = kBrandColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.cloud_outlined, size: size, color: cloudColor),
          // π 符号压在中部偏下（云朵中心视觉位置）
          Padding(
            padding: EdgeInsets.only(top: size * 0.06),
            child: Text(
              'π',
              style: TextStyle(
                fontSize: size * 0.44,
                fontWeight: FontWeight.w700,
                color: piColor,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
