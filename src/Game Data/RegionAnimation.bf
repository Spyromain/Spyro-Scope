using System;
using System.Collections;

namespace SpyroScope {
	struct RegionAnimation {
		public Emulator.Address address;
		public uint8 regionIndex;
		public uint32 count;
		public Vector center;
		public float radius;

		public Mesh sourceNearMesh;
		public Mesh[] nearMeshStates;
		public List<int> nearAnimatedTriangles;

		public struct KeyframeData {
			public uint8 flag, a, nextKeyframe, b, interpolation, fromState, toState, c;
		}

		public uint8 CurrentKeyframe {
			get {
				uint8 currentKeyframe = ?;
				Emulator.ReadFromRAM(address + 2, &currentKeyframe, 1);
				return currentKeyframe;
			}
		}

		public this(Emulator.Address address) {
			this = ?;

			this.address = address;
		}

		public void Dispose() {
			DeleteContainerAndItems!(nearMeshStates);
			delete nearAnimatedTriangles;
		}

		public void Reload(TerrainRegion[] terrainMeshes) mut {
			if (address.IsNull)
				return;

			Emulator.ReadFromRAM(address + 4, &regionIndex, 2);
			Emulator.ReadFromRAM(address + 6, &count, 2);

			uint32 vertexDataOffset = ?;
			Emulator.ReadFromRAM(address + 8, &vertexDataOffset, 4);

			// Analyze the animation
			uint32 keyframeCount = vertexDataOffset >> 3 - 1; // triangleDataOffset / 8
			uint8 highestUsedState = 0;
			for (let keyframeIndex < keyframeCount) {
				(uint8 fromState, uint8 toState) s = ?;
				Emulator.ReadFromRAM(address + 12 + keyframeIndex * 8 + 5, &s, 2);

				highestUsedState = Math.Max(highestUsedState, s.fromState);
				highestUsedState = Math.Max(highestUsedState, s.toState);
			}

			Vector upperBound = .(float.NegativeInfinity,float.NegativeInfinity,float.NegativeInfinity);
			Vector lowerBound = .(float.PositiveInfinity,float.PositiveInfinity,float.PositiveInfinity);

			let stateCount = highestUsedState + 1;
			let vertexCount = count / 4;

			sourceNearMesh = terrainMeshes[regionIndex].nearMesh;

			// Find triangles using these vertices
			let terrainRegionIndicies = terrainMeshes[regionIndex].nearMeshIndices;
			List<uint32> nearAnimatedIndices = scope .();
			nearAnimatedTriangles = new .();
			for (var i = 0; i < terrainRegionIndicies.Count; i += 3) {
				if (terrainRegionIndicies[i] < vertexCount ||
					terrainRegionIndicies[i + 1] < vertexCount ||
					terrainRegionIndicies[i + 2] < vertexCount) {

					nearAnimatedIndices.Add(terrainRegionIndicies[i]);
					nearAnimatedIndices.Add(terrainRegionIndicies[i + 1]);
					nearAnimatedIndices.Add(terrainRegionIndicies[i + 2]);

					nearAnimatedTriangles.Add(i);
				}
			}

			let vertices = scope Vector[vertexCount];
			nearMeshStates = new .[stateCount];
			for (let stateIndex < stateCount) {
				let startVertexState = stateIndex * vertexCount;

				for (let vertexIndex < vertexCount) {
					uint32 packedVertex = ?;
					Emulator.ReadFromRAM(address + vertexDataOffset + ((startVertexState + vertexIndex) * 4), &packedVertex, 4);
					let unpackedVertex = TerrainRegion.UnpackVertex(packedVertex);
					vertices[vertexIndex] = unpackedVertex;

					upperBound.x = Math.Max(upperBound.x, unpackedVertex.x);
					upperBound.y = Math.Max(upperBound.y, unpackedVertex.y);
					upperBound.z = Math.Max(upperBound.z, unpackedVertex.z);
					
					lowerBound.x = Math.Min(lowerBound.x, unpackedVertex.x);
					lowerBound.y = Math.Min(lowerBound.y, unpackedVertex.y);
					lowerBound.z = Math.Min(lowerBound.z, unpackedVertex.z);
				}
				
				center = (upperBound + lowerBound) / 2;
				radius = (upperBound - center).Length();

				Vector[] v = new .[nearAnimatedIndices.Count];
				Vector[] n = new .[nearAnimatedIndices.Count];
				Renderer.Color4[] c = new .[nearAnimatedIndices.Count];

				for (let i < nearAnimatedIndices.Count) {
					v[i] = vertices[nearAnimatedIndices[i]];
					c[i] = .(255,255,255);
					n[i] = .(0,0,1);
				}

				nearMeshStates[stateIndex] = new .(v,n,c);
			}
		}

		public void Update() {
			let currentKeyframe = CurrentKeyframe;

			KeyframeData keyframeData = GetKeyframeData(currentKeyframe);

			let interpolation = (float)keyframeData.interpolation / (256);

			if (keyframeData.fromState >= nearMeshStates.Count || keyframeData.toState >= nearMeshStates.Count) {
				return; // Don't bother since it picked up garbage data
			}

			// Update all vertices that are meant to move between states
			for (let i < nearMeshStates[0].vertices.Count) {
				Vector fromVertex = nearMeshStates[keyframeData.fromState].vertices[i];
				Vector toVertex = nearMeshStates[keyframeData.toState].vertices[i];
				
				sourceNearMesh.vertices[nearAnimatedTriangles[i / 3] + (i % 3)] = fromVertex + (toVertex - fromVertex) * interpolation;
			}

			sourceNearMesh.SetDirty();
		}

		public KeyframeData GetKeyframeData(uint8 keyframeIndex) {
			KeyframeData keyframeData = ?;
			Emulator.ReadFromRAM(address + 12 + ((uint32)keyframeIndex) * 8, &keyframeData, 8);
			return keyframeData;
		}
	}
}
