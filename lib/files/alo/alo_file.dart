import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Parsed model data from a Petroglyph Alamo Object (.ALO) file.
///
/// This first implementation targets 3D model ALO files. Particle-system ALO
/// files use a different structure and are not handled by this parser.
class AloModel {
  const AloModel({
    required this.bones,
    required this.meshes,
    required this.lights,
    required this.proxies,
    required this.dazzleCount,
    required this.bounds,
  });

  final List<AloBone> bones;
  final List<AloMesh> meshes;
  final List<AloLight> lights;
  final List<String> proxies;
  final int dazzleCount;
  final AloBounds bounds;

  int get vertexCount => meshes.fold<int>(
        0,
        (int total, AloMesh mesh) => total + mesh.vertexCount,
      );

  int get triangleCount => meshes.fold<int>(
        0,
        (int total, AloMesh mesh) => total + mesh.triangleCount,
      );
}

class AloBone {
  const AloBone({
    required this.index,
    required this.name,
    required this.parentIndex,
    required this.visible,
    required this.billboardMode,
    required this.absoluteTransform,
  });

  final int index;
  final String name;
  final int parentIndex;
  final bool visible;
  final int billboardMode;

  /// Row-major 4x4 matrix using Direct3D row-vector conventions.
  final List<double> absoluteTransform;
}

class AloMesh {
  const AloMesh({
    required this.name,
    required this.visible,
    required this.collidable,
    required this.attachedBoneIndex,
    required this.bounds,
    required this.subMeshes,
  });

  final String name;
  final bool visible;
  final bool collidable;
  final int attachedBoneIndex;
  final AloBounds bounds;
  final List<AloSubMesh> subMeshes;

  int get vertexCount => subMeshes.fold<int>(
        0,
        (int total, AloSubMesh subMesh) => total + subMesh.vertexCount,
      );

  int get triangleCount => subMeshes.fold<int>(
        0,
        (int total, AloSubMesh subMesh) => total + subMesh.triangleCount,
      );
}

class AloSubMesh {
  const AloSubMesh({
    required this.shader,
    required this.vertexFormat,
    required this.parameters,
    required this.positions,
    required this.normals,
    required this.texCoords,
    required this.colors,
    required this.indices,
    required this.skinBones,
  });

  final String shader;
  final String vertexFormat;
  final Map<String, Object?> parameters;
  final Float32List positions;
  final Float32List normals;
  final Float32List texCoords;
  final Float32List colors;
  final Uint16List indices;
  final List<int> skinBones;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;
  bool get isSkinned => skinBones.isNotEmpty;
}

class AloLight {
  const AloLight({
    required this.name,
    required this.type,
    required this.red,
    required this.green,
    required this.blue,
    required this.intensity,
    required this.attachedBoneIndex,
  });

  final String name;
  final int type;
  final int attachedBoneIndex;
  final double red;
  final double green;
  final double blue;
  final double intensity;
}

class AloBounds {
  const AloBounds({
    required this.minX,
    required this.minY,
    required this.minZ,
    required this.maxX,
    required this.maxY,
    required this.maxZ,
  });

  final double minX;
  final double minY;
  final double minZ;
  final double maxX;
  final double maxY;
  final double maxZ;

  double get centerX => (minX + maxX) * 0.5;
  double get centerY => (minY + maxY) * 0.5;
  double get centerZ => (minZ + maxZ) * 0.5;

  double get radius {
    final double x = maxX - minX;
    final double y = maxY - minY;
    final double z = maxZ - minZ;
    final double diagonal = x * x + y * y + z * z;
    return diagonal > 0 ? sqrt(diagonal) * 0.5 : 1.0;
  }

  static AloBounds fromPositions(Iterable<double> positions) {
    final List<double> values = positions is List<double>
        ? positions
        : positions.toList(growable: false);

    if (values.length < 3) {
      return const AloBounds(
        minX: -1,
        minY: -1,
        minZ: -1,
        maxX: 1,
        maxY: 1,
        maxZ: 1,
      );
    }

    double minX = values[0];
    double maxX = values[0];
    double minY = values[1];
    double maxY = values[1];
    double minZ = values[2];
    double maxZ = values[2];

    for (int i = 3; i + 2 < values.length; i += 3) {
      final double x = values[i];
      final double y = values[i + 1];
      final double z = values[i + 2];

      minX = min(minX, x);
      maxX = max(maxX, x);
      minY = min(minY, y);
      maxY = max(maxY, y);
      minZ = min(minZ, z);
      maxZ = max(maxZ, z);
    }

    return AloBounds(
      minX: minX,
      minY: minY,
      minZ: minZ,
      maxX: maxX,
      maxY: maxY,
      maxZ: maxZ,
    );
  }
}

class AloFileParser {
  static const int _maxChunkDepth = 64;
  static const int _maxElements = 10000000;

  static AloModel parse(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const FormatException('ALO file is too small.');
    }

    final List<_AloChunk> topChunks = _parseChunkRange(
      bytes,
      0,
      bytes.length,
      0,
    );

    final _AloChunk? skeletonChunk = _first(topChunks, 0x200);
    if (skeletonChunk == null) {
      throw const FormatException(
        'This ALO file does not contain a model skeleton. Particle-system ALO files are not supported yet.',
      );
    }

    final List<AloBone> bones = _parseSkeleton(skeletonChunk);
    final List<Object> objectsInFileOrder = [];

    for (final _AloChunk chunk in topChunks) {
      if (chunk.type == 0x400) {
        objectsInFileOrder.add(_parseMesh(chunk));
      } else if (chunk.type == 0x1300) {
        objectsInFileOrder.add(_parseLight(chunk));
      }
    }

    final _AloChunk? connections = _first(topChunks, 0x600);
    final List<String> proxies = [];
    int dazzleCount = 0;
    final Map<int, int> objectBoneAssignments = <int, int>{};

    if (connections != null) {
      final _ConnectionResult result = _parseConnections(
        connections,
        objectsInFileOrder,
        bones.length,
      );
      proxies.addAll(result.proxies);
      dazzleCount = result.dazzles;
      objectBoneAssignments.addAll(result.objectBoneAssignments);
    }

    final List<AloMesh> transformedMeshes = [];
    final List<AloLight> transformedLights = [];
    final List<double> allPositions = [];

    int objectIndex = 0;

    // Connection object indices use the original file order: meshes and lights
    // are interleaved, so apply attachments while walking that same order.
    for (final Object object in objectsInFileOrder) {
      final int attachedBone = objectBoneAssignments[objectIndex] ?? -1;

      if (object is AloMesh) {
        final List<AloSubMesh> transformedSubMeshes = [];

        for (final AloSubMesh subMesh in object.subMeshes) {
          AloSubMesh output = subMesh;

          // Rigid submeshes are attached to the mesh's connected bone.
          // Skinned submeshes use animation-mapping bone indices and are in
          // bind pose at load time, so their original vertices stay in model space.
          if (!subMesh.isSkinned &&
              attachedBone >= 0 &&
              attachedBone < bones.length) {
            output = _applyRigidBoneTransform(
              subMesh,
              bones[attachedBone].absoluteTransform,
            );
          }

          transformedSubMeshes.add(output);
          allPositions.addAll(output.positions);
        }

        transformedMeshes.add(
          AloMesh(
            name: object.name,
            visible: object.visible,
            collidable: object.collidable,
            attachedBoneIndex: attachedBone,
            bounds: object.bounds,
            subMeshes: transformedSubMeshes,
          ),
        );
      } else if (object is AloLight) {
        transformedLights.add(
          AloLight(
            name: object.name,
            type: object.type,
            red: object.red,
            green: object.green,
            blue: object.blue,
            intensity: object.intensity,
            attachedBoneIndex: attachedBone,
          ),
        );
      }

      objectIndex++;
    }

    return AloModel(
      bones: bones,
      meshes: transformedMeshes,
      lights: transformedLights,
      proxies: proxies,
      dazzleCount: dazzleCount,
      bounds: AloBounds.fromPositions(allPositions),
    );
  }

  static List<_AloChunk> _parseChunkRange(
    Uint8List bytes,
    int start,
    int end,
    int depth,
  ) {
    if (depth > _maxChunkDepth) {
      throw const FormatException('ALO chunk nesting is too deep.');
    }

    final ByteData data = ByteData.sublistView(bytes);
    final List<_AloChunk> chunks = [];
    int offset = start;

    while (offset < end) {
      if (end - offset < 8) {
        throw FormatException('Incomplete ALO chunk header at $offset.');
      }

      final int type = data.getUint32(offset, Endian.little);
      final int encodedSize = data.getUint32(offset + 4, Endian.little);
      final bool isGroup = (encodedSize & 0x80000000) != 0;
      final int size = encodedSize & 0x7FFFFFFF;
      final int payloadStart = offset + 8;
      final int payloadEnd = payloadStart + size;

      if (payloadEnd < payloadStart || payloadEnd > end) {
        throw FormatException(
          'ALO chunk 0x${type.toRadixString(16)} has an invalid size at $offset.',
        );
      }

      final List<_AloChunk> children = isGroup
          ? _parseChunkRange(bytes, payloadStart, payloadEnd, depth + 1)
          : const <_AloChunk>[];

      chunks.add(
        _AloChunk(
          type: type,
          payload: Uint8List.sublistView(bytes, payloadStart, payloadEnd),
          children: children,
          offset: offset,
        ),
      );

      offset = payloadEnd;
    }

    return chunks;
  }

  static List<AloBone> _parseSkeleton(_AloChunk skeleton) {
    final _AloChunk? header = _first(skeleton.children, 0x201);
    if (header == null || header.payload.length < 4) {
      throw const FormatException('ALO skeleton header is missing or invalid.');
    }

    final int boneCount = _uint32(header.payload, 0);
    if (boneCount > 100000) {
      throw const FormatException('ALO bone count is unreasonable.');
    }

    final List<AloBone> bones = [];
    final List<_AloChunk> boneChunks = _all(skeleton.children, 0x202);

    if (boneChunks.length != boneCount) {
      throw FormatException(
        'ALO skeleton declares $boneCount bones but contains ${boneChunks.length}.',
      );
    }

    for (int i = 0; i < boneChunks.length; i++) {
      final _AloChunk boneChunk = boneChunks[i];
      final _AloChunk? nameChunk = _first(boneChunk.children, 0x203);
      final _AloChunk? dataChunk = _first(boneChunk.children, 0x205) ??
          _first(boneChunk.children, 0x206);

      if (nameChunk == null || dataChunk == null) {
        throw FormatException('ALO bone $i is missing name or transform data.');
      }

      final bool hasBillboard = dataChunk.type == 0x206;
      final int expectedSize = hasBillboard ? 60 : 56;
      if (dataChunk.payload.length < expectedSize) {
        throw FormatException('ALO bone $i transform data is truncated.');
      }

      final ByteData data = ByteData.sublistView(dataChunk.payload);
      final int parentIndex = data.getInt32(0, Endian.little);
      final bool visible = data.getUint32(4, Endian.little) != 0;
      final int billboardMode = hasBillboard
          ? data.getUint32(8, Endian.little)
          : 0;
      final int matrixOffset = hasBillboard ? 12 : 8;
      final List<double> values = List<double>.generate(
        12,
        (int index) => data.getFloat32(
          matrixOffset + index * 4,
          Endian.little,
        ),
      );

      if (parentIndex >= i || parentIndex < -1) {
        throw FormatException(
          'ALO bone $i has invalid parent index $parentIndex.',
        );
      }

      final List<double> relative = _matrixFromBoneValues(values);
      final List<double> absolute = parentIndex >= 0
          ? _multiply4x4(relative, bones[parentIndex].absoluteTransform)
          : relative;

      bones.add(
        AloBone(
          index: i,
          name: _readString(nameChunk.payload),
          parentIndex: parentIndex,
          visible: visible,
          billboardMode: billboardMode,
          absoluteTransform: absolute,
        ),
      );
    }

    return bones;
  }

  static AloMesh _parseMesh(_AloChunk chunk) {
    final _AloChunk? nameChunk = _first(chunk.children, 0x401);
    final _AloChunk? infoChunk = _first(chunk.children, 0x402);

    if (nameChunk == null || infoChunk == null || infoChunk.payload.length < 40) {
      throw const FormatException('ALO mesh is missing its name or info chunk.');
    }

    final String name = _readString(nameChunk.payload);
    final ByteData info = ByteData.sublistView(infoChunk.payload);

    final int materialCount = info.getUint32(0, Endian.little);
    if (materialCount > 100000) {
      throw FormatException('ALO mesh "$name" has an unreasonable material count.');
    }

    final AloBounds bounds = AloBounds(
      minX: info.getFloat32(4, Endian.little),
      minY: info.getFloat32(8, Endian.little),
      minZ: info.getFloat32(12, Endian.little),
      maxX: info.getFloat32(16, Endian.little),
      maxY: info.getFloat32(20, Endian.little),
      maxZ: info.getFloat32(24, Endian.little),
    );

    final bool visible = info.getUint32(32, Endian.little) == 0;
    final bool collidable = info.getUint32(36, Endian.little) != 0;

    final List<_AloChunk> materialChunks = _all(chunk.children, 0x10100);
    final List<_AloChunk> dataChunks = _all(chunk.children, 0x10000);

    if (materialChunks.length < materialCount || dataChunks.length < materialCount) {
      throw FormatException('ALO mesh "$name" has incomplete sub-mesh data.');
    }

    final List<AloSubMesh> subMeshes = [];

    for (int i = 0; i < materialCount; i++) {
      final _AloMaterial material = _parseMaterial(materialChunks[i]);
      final AloSubMesh subMesh = _parseSubMesh(dataChunks[i], material);
      subMeshes.add(subMesh);
    }

    return AloMesh(
      name: name,
      visible: visible,
      collidable: collidable,
      attachedBoneIndex: -1,
      bounds: bounds,
      subMeshes: subMeshes,
    );
  }

  static _AloMaterial _parseMaterial(_AloChunk chunk) {
    final _AloChunk? nameChunk = _first(chunk.children, 0x10101);
    final String shader = nameChunk == null ? 'Unknown' : _readString(nameChunk.payload);
    final Map<String, Object?> parameters = {};

    for (final _AloChunk parameterChunk in chunk.children) {
      if (parameterChunk.type < 0x10102 || parameterChunk.type > 0x10106) {
        continue;
      }

      final Map<int, Uint8List> mini = _parseMiniChunks(parameterChunk.payload);
      final Uint8List? nameBytes = mini[1];
      final Uint8List? valueBytes = mini[2];
      if (nameBytes == null || valueBytes == null) {
        continue;
      }

      final String parameterName = _readString(nameBytes);
      final ByteData value = ByteData.sublistView(valueBytes);

      switch (parameterChunk.type) {
        case 0x10102:
          if (valueBytes.length >= 4) {
            parameters[parameterName] = value.getUint32(0, Endian.little);
          }
          break;
        case 0x10103:
          if (valueBytes.length >= 4) {
            parameters[parameterName] = value.getFloat32(0, Endian.little);
          }
          break;
        case 0x10104:
          if (valueBytes.length >= 12) {
            parameters[parameterName] = AloVector4(
              value.getFloat32(0, Endian.little),
              value.getFloat32(4, Endian.little),
              value.getFloat32(8, Endian.little),
              1,
            );
          }
          break;
        case 0x10105:
          parameters[parameterName] = _readString(valueBytes);
          break;
        case 0x10106:
          if (valueBytes.length >= 16) {
            parameters[parameterName] = AloVector4(
              value.getFloat32(0, Endian.little),
              value.getFloat32(4, Endian.little),
              value.getFloat32(8, Endian.little),
              value.getFloat32(12, Endian.little),
            );
          }
          break;
      }
    }

    return _AloMaterial(shader, parameters);
  }

  static AloSubMesh _parseSubMesh(_AloChunk chunk, _AloMaterial material) {
    final _AloChunk? headerChunk = _first(chunk.children, 0x10001);
    final _AloChunk? formatChunk = _first(chunk.children, 0x10002);
    final _AloChunk? vertexChunk = _first(chunk.children, 0x10007) ??
        _first(chunk.children, 0x10005);
    final _AloChunk? indexChunk = _first(chunk.children, 0x10004);

    if (headerChunk == null ||
        headerChunk.payload.length < 8 ||
        formatChunk == null ||
        vertexChunk == null ||
        indexChunk == null) {
      throw const FormatException('ALO sub-mesh is missing geometry data.');
    }

    final ByteData header = ByteData.sublistView(headerChunk.payload);
    final int vertexCount = header.getUint32(0, Endian.little);
    final int primitiveCount = header.getUint32(4, Endian.little);

    if (vertexCount > _maxElements || primitiveCount > _maxElements) {
      throw const FormatException('ALO geometry contains unreasonable element counts.');
    }

    final int stride = vertexChunk.type == 0x10007 ? 144 : 128;
    final int requiredVertexBytes = vertexCount * stride;
    if (vertexChunk.payload.length < requiredVertexBytes) {
      throw const FormatException('ALO vertex buffer is truncated.');
    }

    final int indexCount = primitiveCount * 3;
    final int requiredIndexBytes = indexCount * 2;
    if (indexChunk.payload.length < requiredIndexBytes) {
      throw const FormatException('ALO index buffer is truncated.');
    }

    final ByteData vertices = ByteData.sublistView(vertexChunk.payload);
    final Float32List positions = Float32List(vertexCount * 3);
    final Float32List normals = Float32List(vertexCount * 3);
    final Float32List texCoords = Float32List(vertexCount * 2);
    final Float32List colors = Float32List(vertexCount * 4);

    for (int i = 0; i < vertexCount; i++) {
      final int base = i * stride;
      final int p = i * 3;
      final int uv = i * 2;
      final int color = i * 4;

      positions[p] = vertices.getFloat32(base, Endian.little);
      positions[p + 1] = vertices.getFloat32(base + 4, Endian.little);
      positions[p + 2] = vertices.getFloat32(base + 8, Endian.little);

      normals[p] = vertices.getFloat32(base + 12, Endian.little);
      normals[p + 1] = vertices.getFloat32(base + 16, Endian.little);
      normals[p + 2] = vertices.getFloat32(base + 20, Endian.little);

      // ALO stores four float2 texture coordinate sets; the first is UV0.
      texCoords[uv] = vertices.getFloat32(base + 24, Endian.little);
      texCoords[uv + 1] = vertices.getFloat32(base + 28, Endian.little);

      // The old and current master-vertex layouts share the color offset.
      colors[color] = vertices.getFloat32(base + 80, Endian.little);
      colors[color + 1] = vertices.getFloat32(base + 84, Endian.little);
      colors[color + 2] = vertices.getFloat32(base + 88, Endian.little);
      colors[color + 3] = vertices.getFloat32(base + 92, Endian.little);
    }

    final ByteData indexData = ByteData.sublistView(indexChunk.payload);
    final Uint16List indices = Uint16List(indexCount);
    for (int i = 0; i < indexCount; i++) {
      final int value = indexData.getUint16(i * 2, Endian.little);
      if (value >= vertexCount) {
        throw FormatException('ALO index $value exceeds vertex count $vertexCount.');
      }
      indices[i] = value;
    }

    final _AloChunk? skinChunk = _first(chunk.children, 0x10006);
    final List<int> skinBones = [];
    if (skinChunk != null) {
      final ByteData skinData = ByteData.sublistView(skinChunk.payload);
      for (int offset = 0; offset + 4 <= skinChunk.payload.length && skinBones.length < 24; offset += 4) {
        skinBones.add(skinData.getUint32(offset, Endian.little));
      }
    }

    final String vertexFormat = _readString(formatChunk.payload);

    return AloSubMesh(
      shader: material.shader,
      vertexFormat: vertexFormat,
      parameters: material.parameters,
      positions: positions,
      normals: normals,
      texCoords: texCoords,
      colors: colors,
      indices: indices,
      skinBones: skinBones,
    );
  }

  static AloLight _parseLight(_AloChunk chunk) {
    final _AloChunk? nameChunk = _first(chunk.children, 0x1301);
    final _AloChunk? infoChunk = _first(chunk.children, 0x1302);
    if (nameChunk == null || infoChunk == null || infoChunk.payload.length < 36) {
      throw const FormatException('ALO light is missing its name or info data.');
    }

    final ByteData data = ByteData.sublistView(infoChunk.payload);
    return AloLight(
      name: _readString(nameChunk.payload),
      type: data.getUint32(0, Endian.little),
      red: data.getFloat32(4, Endian.little),
      green: data.getFloat32(8, Endian.little),
      blue: data.getFloat32(12, Endian.little),
      intensity: data.getFloat32(16, Endian.little),
      attachedBoneIndex: -1,
    );
  }

  static _ConnectionResult _parseConnections(
    _AloChunk chunk,
    List<Object> objects,
    int boneCount,
  ) {
    final _AloChunk? headerChunk = _first(chunk.children, 0x601);
    if (headerChunk == null) {
      throw const FormatException('ALO connections header is missing.');
    }

    final Map<int, Uint8List> header = _parseMiniChunks(headerChunk.payload);
    final int connectionCount = _readMiniUInt(header[1]);
    final int proxyCount = _readMiniUInt(header[4]);
    final int dazzleCount = _readMiniUInt(header[9]);

    final List<_AloChunk> connectionChunks = _all(chunk.children, 0x602);
    final List<_AloChunk> proxyChunks = _all(chunk.children, 0x603);
    final List<_AloChunk> dazzleChunks = _all(chunk.children, 0x604);

    if (connectionChunks.length != connectionCount) {
      throw FormatException(
        'ALO connections header declares $connectionCount object connections, '
        'but ${connectionChunks.length} were found.',
      );
    }
    if (proxyChunks.length != proxyCount) {
      throw FormatException(
        'ALO connections header declares $proxyCount proxies, '
        'but ${proxyChunks.length} were found.',
      );
    }
    if (dazzleCount != 0 && dazzleChunks.length != dazzleCount) {
      throw FormatException(
        'ALO connections header declares $dazzleCount dazzles, '
        'but ${dazzleChunks.length} were found.',
      );
    }

    final Map<int, int> objectBoneAssignments = <int, int>{};

    for (final _AloChunk connection in connectionChunks) {
      final Map<int, Uint8List> mini = _parseMiniChunks(connection.payload);
      final int objectIndex = _readMiniUInt(mini[2]);
      final int boneIndex = _readMiniUInt(mini[3]);

      if (objectIndex < 0 || objectIndex >= objects.length ||
          boneIndex < 0 || boneIndex >= boneCount) {
        throw FormatException(
          'ALO object connection references object $objectIndex or bone $boneIndex outside the model.',
        );
      }

      objectBoneAssignments[objectIndex] = boneIndex;
    }

    final List<String> proxies = [];
    for (final _AloChunk proxy in proxyChunks) {
      final Map<int, Uint8List> mini = _parseMiniChunks(proxy.payload);
      final Uint8List? name = mini[5];
      final int boneIndex = _readMiniUInt(mini[6]);

      if (name == null || boneIndex < 0 || boneIndex >= boneCount) {
        throw const FormatException('ALO proxy has an invalid name or bone index.');
      }

      proxies.add(_readString(name));
    }

    return _ConnectionResult(
      proxies: proxies,
      dazzles: dazzleCount,
      objectBoneAssignments: objectBoneAssignments,
    );
  }

  static AloSubMesh _applyRigidBoneTransform(
    AloSubMesh subMesh,
    List<double> matrix,
  ) {
    final Float32List positions = Float32List.fromList(subMesh.positions);
    final Float32List normals = Float32List.fromList(subMesh.normals);

    for (int i = 0; i < positions.length; i += 3) {
      final double x = positions[i];
      final double y = positions[i + 1];
      final double z = positions[i + 2];

      positions[i] = x * matrix[0] + y * matrix[4] + z * matrix[8] + matrix[12];
      positions[i + 1] = x * matrix[1] + y * matrix[5] + z * matrix[9] + matrix[13];
      positions[i + 2] = x * matrix[2] + y * matrix[6] + z * matrix[10] + matrix[14];

      final double nx = normals[i];
      final double ny = normals[i + 1];
      final double nz = normals[i + 2];

      double tx = nx * matrix[0] + ny * matrix[4] + nz * matrix[8];
      double ty = nx * matrix[1] + ny * matrix[5] + nz * matrix[9];
      double tz = nx * matrix[2] + ny * matrix[6] + nz * matrix[10];
      final double length = _sqrt(tx * tx + ty * ty + tz * tz);
      if (length > 0) {
        tx /= length;
        ty /= length;
        tz /= length;
      }

      normals[i] = tx;
      normals[i + 1] = ty;
      normals[i + 2] = tz;
    }

    return AloSubMesh(
      shader: subMesh.shader,
      vertexFormat: subMesh.vertexFormat,
      parameters: subMesh.parameters,
      positions: positions,
      normals: normals,
      texCoords: subMesh.texCoords,
      colors: subMesh.colors,
      indices: subMesh.indices,
      skinBones: subMesh.skinBones,
    );
  }

  static List<double> _matrixFromBoneValues(List<double> values) {
    // The original viewer reads three rows of four floats and transposes the
    // resulting Direct3D matrix. Store the resulting row-major 4x4 matrix.
    return <double>[
      values[0], values[4], values[8], 0,
      values[1], values[5], values[9], 0,
      values[2], values[6], values[10], 0,
      values[3], values[7], values[11], 1,
    ];
  }

  static List<double> _multiply4x4(List<double> a, List<double> b) {
    final List<double> result = List<double>.filled(16, 0);
    for (int row = 0; row < 4; row++) {
      for (int column = 0; column < 4; column++) {
        double value = 0;
        for (int k = 0; k < 4; k++) {
          value += a[row * 4 + k] * b[k * 4 + column];
        }
        result[row * 4 + column] = value;
      }
    }
    return result;
  }

  static Map<int, Uint8List> _parseMiniChunks(Uint8List payload) {
    final Map<int, Uint8List> chunks = {};
    int offset = 0;

    while (offset < payload.length) {
      if (payload.length - offset < 2) {
        throw const FormatException('Incomplete ALO mini-chunk header.');
      }

      final int type = payload[offset];
      final int size = payload[offset + 1];
      final int start = offset + 2;
      final int end = start + size;

      if (end > payload.length) {
        throw const FormatException('ALO mini-chunk exceeds its parent chunk.');
      }

      chunks[type] = Uint8List.sublistView(payload, start, end);
      offset = end;
    }

    return chunks;
  }

  static int _readMiniUInt(Uint8List? bytes) {
    if (bytes == null || bytes.length < 4) return 0;
    return ByteData.sublistView(bytes).getUint32(0, Endian.little);
  }

  static int _uint32(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes).getUint32(offset, Endian.little);

  static String _readString(Uint8List bytes) {
    int end = bytes.indexOf(0);
    if (end < 0) end = bytes.length;
    return utf8.decode(bytes.sublist(0, end), allowMalformed: true);
  }

  static _AloChunk? _first(List<_AloChunk> chunks, int type) {
    for (final _AloChunk chunk in chunks) {
      if (chunk.type == type) return chunk;
    }
    return null;
  }

  static List<_AloChunk> _all(List<_AloChunk> chunks, int type) =>
      chunks.where((_AloChunk chunk) => chunk.type == type).toList();

  static double _sqrt(double value) => value <= 0 ? 0 : _sqrtNewton(value);

  static double _sqrtNewton(double value) {
    double x = value;
    double previous = 0;
    while (x != previous) {
      previous = x;
      x = (x + value / x) * 0.5;
    }
    return x;
  }
}

class AloVector4 {
  const AloVector4(this.x, this.y, this.z, this.w);

  final double x;
  final double y;
  final double z;
  final double w;
}

class _AloChunk {
  const _AloChunk({
    required this.type,
    required this.payload,
    required this.children,
    required this.offset,
  });

  final int type;
  final Uint8List payload;
  final List<_AloChunk> children;
  final int offset;
}

class _AloMaterial {
  const _AloMaterial(this.shader, this.parameters);

  final String shader;
  final Map<String, Object?> parameters;
}

class _ConnectionResult {
  const _ConnectionResult({
    required this.proxies,
    required this.dazzles,
    required this.objectBoneAssignments,
  });

  final List<String> proxies;
  final int dazzles;
  final Map<int, int> objectBoneAssignments;
}
