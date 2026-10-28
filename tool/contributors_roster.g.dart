// Copyright 2026 The Flutter Authors.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contributors_roster.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ContributorEntry _$ContributorEntryFromJson(Map<String, dynamic> json) =>
    ContributorEntry(
      username: json['username'] == null ? '' : _trimString(json['username']),
      role: _trimNullableString(json['role']),
      team: _trimNullableString(json['team']),
      discord: _trimNullableString(json['discord']),
      graceUntil: _trimNullableString(json['grace_until']),
    );

Map<String, dynamic> _$ContributorEntryToJson(ContributorEntry instance) =>
    <String, dynamic>{
      'username': instance.username,
      'role': instance.role,
      'team': instance.team,
      'discord': instance.discord,
      'grace_until': instance.graceUntil,
    };

MaintainersRoster _$MaintainersRosterFromJson(Map<String, dynamic> json) =>
    MaintainersRoster(
      googlers: (json['googlers'] as List<dynamic>?)
              ?.map((e) => ContributorEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      partners: (json['partners'] as List<dynamic>?)
              ?.map((e) => ContributorEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$MaintainersRosterToJson(MaintainersRoster instance) =>
    <String, dynamic>{
      'googlers': instance.googlers.map((e) => e.toJson()).toList(),
      'partners': instance.partners.map((e) => e.toJson()).toList(),
    };

ContributorsRoster _$ContributorsRosterFromJson(Map<String, dynamic> json) =>
    ContributorsRoster(
      maintainers: json['maintainers'] == null
          ? const MaintainersRoster()
          : MaintainersRoster.fromJson(
              json['maintainers'] as Map<String, dynamic>),
      committers: (json['committers'] as List<dynamic>?)
              ?.map((e) => ContributorEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      reviewers: (json['reviewers'] as List<dynamic>?)
              ?.map((e) => ContributorEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      dashEmeritus: (json['dash_emeritus'] as List<dynamic>?)
              ?.map((e) => ContributorEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$ContributorsRosterToJson(ContributorsRoster instance) =>
    <String, dynamic>{
      'maintainers': instance.maintainers.toJson(),
      'committers': instance.committers.map((e) => e.toJson()).toList(),
      'reviewers': instance.reviewers.map((e) => e.toJson()).toList(),
      'dash_emeritus': instance.dashEmeritus.map((e) => e.toJson()).toList(),
    };
