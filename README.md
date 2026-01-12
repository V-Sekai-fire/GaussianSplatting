# Gaussian Splatting Godot Implementation

This project implements support for KHR_gaussian_splatting extension in Godot Engine, using the Compatibility renderer for WebGL2 compatibility.

## Features

- Loads glTF files with KHR_gaussian_splatting extension
- Renders Gaussian splats as billboards with basic Gaussian falloff
- Supports position, scale, rotation, opacity, and spherical harmonics (degree 3)
- TODO: Sorts splats by distance for correct blending

## Usage

1. Open the project in Godot 4.1+
2. Import your glTF file with Gaussian splats
3. Run the scene
