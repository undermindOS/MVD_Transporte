// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bus_stop.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BusStopAdapter extends TypeAdapter<BusStop> {
  @override
  final int typeId = 0;

  @override
  BusStop read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BusStop(
      id: fields[0] as int,
      name: fields[1] as String,
      latitude: fields[2] as double,
      longitude: fields[3] as double,
      lines: (fields[4] as List).cast<String>(),
      notificationsEnabled: fields[5] as bool,
      etaAlertMinutes: fields[6] as int,
      alertDays: fields[7] == null
          ? [1, 2, 3, 4, 5, 6, 7]
          : (fields[7] as List).cast<int>(),
      alertFromMinute: fields[8] == null ? 0 : fields[8] as int,
      alertToMinute: fields[9] == null ? 1440 : fields[9] as int,
    );
  }

  @override
  void write(BinaryWriter writer, BusStop obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.latitude)
      ..writeByte(3)
      ..write(obj.longitude)
      ..writeByte(4)
      ..write(obj.lines)
      ..writeByte(5)
      ..write(obj.notificationsEnabled)
      ..writeByte(6)
      ..write(obj.etaAlertMinutes)
      ..writeByte(7)
      ..write(obj.alertDays)
      ..writeByte(8)
      ..write(obj.alertFromMinute)
      ..writeByte(9)
      ..write(obj.alertToMinute);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusStopAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
