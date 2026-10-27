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
      alertDays: fields[7] == null
          ? [1, 2, 3, 4, 5, 6, 7]
          : (fields[7] as List).cast<int>(),
      alertFromMinute: fields[8] == null ? 0 : fields[8] as int,
      alertToMinute: fields[9] == null ? 1440 : fields[9] as int,
      preferredDestinations:
          fields[10] == null ? [] : (fields[10] as List).cast<String>(),
      preferredVariantIds:
          fields[11] == null ? [] : (fields[11] as List).cast<int>(),
    );
  }

  @override
  void write(BinaryWriter writer, RouteAlert obj) {
    writer
      ..writeByte(12)
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
      ..write(obj.alertMinutes)
      ..writeByte(7)
      ..write(obj.alertDays)
      ..writeByte(8)
      ..write(obj.alertFromMinute)
      ..writeByte(9)
      ..write(obj.alertToMinute)
      ..writeByte(10)
      ..write(obj.preferredDestinations)
      ..writeByte(11)
      ..write(obj.preferredVariantIds);
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
