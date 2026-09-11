// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'route_alert.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class RouteAlertAdapter extends TypeAdapter<RouteAlert> {
  @override
  final int typeId = 1;

  @override
  RouteAlert read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return RouteAlert(
      id: fields[0] as int,
      originStopId: fields[1] as int,
      originName: fields[2] as String,
      destinationName: fields[3] as String,
      preferredLines: (fields[4] as List).cast<String>(),
      enabled: fields[5] as bool,
      alertMinutes: fields[6] as int,
    );
  }

  @override
  void write(BinaryWriter writer, RouteAlert obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.originStopId)
      ..writeByte(2)
      ..write(obj.originName)
      ..writeByte(3)
      ..write(obj.destinationName)
      ..writeByte(4)
      ..write(obj.preferredLines)
      ..writeByte(5)
      ..write(obj.enabled)
      ..writeByte(6)
      ..write(obj.alertMinutes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteAlertAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
