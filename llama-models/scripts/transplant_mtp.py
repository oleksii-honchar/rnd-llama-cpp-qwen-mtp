#!/usr/bin/env python3
"""Transplant MTP block tensors from a source GGUF into a target GGUF.

Uses a raw binary approach — reads both GGUF files, writes the output file
manually (header, KVs, tensor info, tensor data), and copies tensor data
as raw bytes from the source files. This preserves the exact on-disk layout
including per-row metadata for quantization types like IQ4_KS.

Based on llama.cpp PR #22673 convert_hf_to_gguf.py changes:
  - block_count = num_hidden_layers + mtp_num_hidden_layers (64 + 1 = 65)
  - nextn_predict_layers = 1
  - MTP tensors are named model.layers.64.*

Inspired by: https://gist.github.com/buzz/1c439684d5e3f36492ae9f64ef7e3f67

Usage:
    python transplant_mtp.py --target <target.gguf> --source <source.gguf> --output <output.gguf>
"""

import argparse
import hashlib
import re
import struct
import sys
from pathlib import Path

import gguf
import numpy as np


def get_field_value(reader: gguf.GGUFReader, key: str):
    """Safely get a field value from GGUFReader."""
    field = reader.get_field(key)
    return field.contents() if field else None


def calculate_on_disk_sizes(tensors, file_size):
    """Calculate on-disk size for each tensor (including per-row metadata/padding)."""
    n_tensors = len(tensors)
    sizes = []
    for i in range(n_tensors):
        if i < n_tensors - 1:
            sizes.append(tensors[i + 1].data_offset - tensors[i].data_offset)
        else:
            sizes.append(file_size - tensors[i].data_offset)
    return sizes


def write_kv_value(fout, kv_type, value):
    """Write a KV value to the output file."""
    if kv_type == gguf.GGUFValueType.STRING:
        value_bytes = value.encode("utf-8")
        fout.write(struct.pack("<Q", len(value_bytes)))
        fout.write(value_bytes)
    elif kv_type == gguf.GGUFValueType.ARRAY:
        pass  # Handled separately
    elif kv_type in (gguf.GGUFValueType.UINT8, gguf.GGUFValueType.INT8, gguf.GGUFValueType.BOOL):
        fout.write(struct.pack("<B", value))
    elif kv_type in (gguf.GGUFValueType.UINT16, gguf.GGUFValueType.INT16):
        fout.write(struct.pack("<H", value))
    elif kv_type in (gguf.GGUFValueType.UINT32, gguf.GGUFValueType.INT32):
        fout.write(struct.pack("<I", value))
    elif kv_type == gguf.GGUFValueType.FLOAT32:
        fout.write(struct.pack("<f", value))
    elif kv_type in (gguf.GGUFValueType.UINT64, gguf.GGUFValueType.INT64):
        fout.write(struct.pack("<Q", value))
    elif kv_type == gguf.GGUFValueType.FLOAT64:
        fout.write(struct.pack("<d", value))


def write_array_value(fout, sub_type, arr):
    """Write an array KV value to the output file."""
    fout.write(struct.pack("<I", int(sub_type)))
    fout.write(struct.pack("<Q", len(arr)))
    for elem in arr:
        if sub_type == gguf.GGUFValueType.STRING:
            elem_bytes = elem.encode("utf-8")
            fout.write(struct.pack("<Q", len(elem_bytes)))
            fout.write(elem_bytes)
        elif sub_type in (gguf.GGUFValueType.UINT8, gguf.GGUFValueType.INT8, gguf.GGUFValueType.BOOL):
            fout.write(struct.pack("<B", elem))
        elif sub_type in (gguf.GGUFValueType.UINT16, gguf.GGUFValueType.INT16):
            fout.write(struct.pack("<H", elem))
        elif sub_type in (gguf.GGUFValueType.UINT32, gguf.GGUFValueType.INT32):
            fout.write(struct.pack("<I", elem))
        elif sub_type == gguf.GGUFValueType.FLOAT32:
            fout.write(struct.pack("<f", elem))
        elif sub_type in (gguf.GGUFValueType.UINT64, gguf.GGUFValueType.INT64):
            fout.write(struct.pack("<Q", elem))
        elif sub_type == gguf.GGUFValueType.FLOAT64:
            fout.write(struct.pack("<d", elem))


def transplant_mtp(target_path: str, source_path: str, output_path: str) -> None:
    """Transplant MTP tensors from source into target GGUF using raw binary approach."""

    # ------------------------------------------------------------------
    # 1. Open both files
    # ------------------------------------------------------------------
    print(f"[transplant_mtp] Reading target GGUF: {target_path}")
    target_reader = gguf.GGUFReader(target_path)
    print(f"[transplant_mtp]   Target has {len(target_reader.tensors)} tensors, {len([k for k in target_reader.fields if not k.startswith('GGUF.')])} fields")

    print(f"[transplant_mtp] Reading source GGUF: {source_path}")
    source_reader = gguf.GGUFReader(source_path)
    print(f"[transplant_mtp]   Source has {len(source_reader.tensors)} tensors, {len([k for k in source_reader.fields if not k.startswith('GGUF.')])} fields")

    target_file_size = Path(target_path).stat().st_size
    source_file_size = Path(source_path).stat().st_size

    # ------------------------------------------------------------------
    # 2. Read architecture and MTP metadata
    # ------------------------------------------------------------------
    arch = get_field_value(target_reader, "general.architecture")
    if arch is None:
        print("[transplant_mtp] ERROR: Target GGUF has no general.architecture key", file=sys.stderr)
        sys.exit(1)

    block_count_key = f"{arch}.block_count"
    nextn_key = f"{arch}.nextn_predict_layers"

    source_block_count = get_field_value(source_reader, block_count_key)
    source_nextn = get_field_value(source_reader, nextn_key)
    if source_nextn is None:
        print("[transplant_mtp] ERROR: Source GGUF has no nextn_predict_layers key", file=sys.stderr)
        sys.exit(1)

    target_block_count = get_field_value(target_reader, block_count_key)
    if target_block_count is None:
        # Infer block_count from the highest block number in tensor names
        blk_re = re.compile(r"blk\.(\d+)\.")
        max_blk = 0
        for t in target_reader.tensors:
            m = blk_re.search(t.name)
            if m:
                blk = int(m.group(1))
                if blk > max_blk:
                    max_blk = blk
        target_block_count = max_blk + 1
        print(f"[transplant_mtp]   block_count not in target GGUF, inferred: {target_block_count}")

    print(f"\n[transplant_mtp] Arch: {arch}")
    print(f"[transplant_mtp] Target block_count: {target_block_count}")
    print(f"[transplant_mtp] Source block_count: {source_block_count}, nextn_predict_layers: {source_nextn}")

    # Identify extra tensors in the source (blocks beyond target's count)
    source_extra = [
        t
        for t in source_reader.tensors
        if t.name.startswith(f"blk.{target_block_count}.")
    ]
    print(f"\n[transplant_mtp] Extra tensors to transplant: {len(source_extra)}")
    if not source_extra:
        print(f"[transplant_mtp] ERROR: No tensors found with prefix 'blk.{target_block_count}.' in source", file=sys.stderr)
        sys.exit(1)

    # ------------------------------------------------------------------
    # 3. Prepare tensor lists and calculate sizes
    # ------------------------------------------------------------------
    all_tensors = list(target_reader.tensors) + source_extra

    # Calculate on-disk sizes for both files (including per-row metadata)
    target_on_disk_sizes = calculate_on_disk_sizes(target_reader.tensors, target_file_size)
    source_on_disk_sizes = calculate_on_disk_sizes(source_reader.tensors, source_file_size)

    # Create mapping for source tensors
    source_tensor_map = {
        t.name: (t, size)
        for t, size in zip(source_reader.tensors, source_on_disk_sizes)
    }

    # ------------------------------------------------------------------
    # 4. Write output file
    # ------------------------------------------------------------------
    print(f"\n[transplant_mtp] Writing output: {output_path}")

    with (
        open(target_path, "rb") as target_fin,
        open(source_path, "rb") as source_fin,
        open(output_path, "wb") as fout,
    ):
        # 4.1 Write header
        fout.write(b"GGUF")  # Magic
        fout.write(struct.pack("<I", 3))  # Version
        fout.write(struct.pack("<Q", len(all_tensors)))  # Tensor count

        # Calculate KV count
        target_kv_keys = [k for k in target_reader.fields.keys() if not k.startswith("GGUF.")]
        kv_count = len(target_kv_keys)
        kv_count -= 1  # Remove block_count (we'll override it)
        kv_count += 1  # block_count override
        kv_count += 1  # nextn_predict_layers

        # Add source-only KVs
        for key in source_reader.fields:
            if (
                not key.startswith("GGUF.")
                and key not in target_reader.fields
                and key != block_count_key
                and key != nextn_key
            ):
                kv_count += 1

        fout.write(struct.pack("<Q", kv_count))  # KV count

        # 4.2 Write KV data from target (with block_count override)
        written_keys = set()

        for key, field in target_reader.fields.items():
            if key.startswith("GGUF."):
                continue
            if key == block_count_key:
                continue  # Override later

            key_bytes = key.encode("utf-8")
            fout.write(struct.pack("<Q", len(key_bytes)))
            fout.write(key_bytes)

            kv_type = field.types[0]
            fout.write(struct.pack("<I", int(kv_type)))

            if kv_type == gguf.GGUFValueType.STRING:
                write_kv_value(fout, kv_type, field.contents())
            elif kv_type == gguf.GGUFValueType.ARRAY:
                sub_type = field.types[1] if len(field.types) > 1 else gguf.GGUFValueType.FLOAT32
                write_array_value(fout, sub_type, field.contents())
            else:
                write_kv_value(fout, kv_type, field.contents())

            written_keys.add(key)

        # Override block_count with source value
        key_bytes = block_count_key.encode("utf-8")
        fout.write(struct.pack("<Q", len(key_bytes)))
        fout.write(key_bytes)
        fout.write(struct.pack("<I", int(gguf.GGUFValueType.UINT32)))
        fout.write(struct.pack("<I", source_block_count))
        written_keys.add(block_count_key)

        # Add nextn_predict_layers from source
        key_bytes = nextn_key.encode("utf-8")
        fout.write(struct.pack("<Q", len(key_bytes)))
        fout.write(key_bytes)
        fout.write(struct.pack("<I", int(gguf.GGUFValueType.UINT32)))
        fout.write(struct.pack("<I", source_nextn))
        written_keys.add(nextn_key)

        # Copy source-only KVs
        for key, field in source_reader.fields.items():
            if key.startswith("GGUF.") or key in written_keys or key == nextn_key:
                continue

            key_bytes = key.encode("utf-8")
            fout.write(struct.pack("<Q", len(key_bytes)))
            fout.write(key_bytes)

            kv_type = field.types[0]
            fout.write(struct.pack("<I", int(kv_type)))

            if kv_type == gguf.GGUFValueType.STRING:
                write_kv_value(fout, kv_type, field.contents())
            elif kv_type == gguf.GGUFValueType.ARRAY:
                sub_type = field.types[1] if len(field.types) > 1 else gguf.GGUFValueType.FLOAT32
                write_array_value(fout, sub_type, field.contents())
            else:
                write_kv_value(fout, kv_type, field.contents())

        # 4.3 Write tensor info
        current_offset = 0
        tensor_offsets = []
        for i, tensor in enumerate(all_tensors):
            if i < len(target_reader.tensors):
                size = target_on_disk_sizes[i]
            else:
                _, size = source_tensor_map[tensor.name]
            tensor_offsets.append(current_offset)
            current_offset += size

        for i, tensor in enumerate(all_tensors):
            name_bytes = tensor.name.encode("utf-8")
            fout.write(struct.pack("<Q", len(name_bytes)))
            fout.write(name_bytes)

            shape = tensor.shape.tolist()
            fout.write(struct.pack("<I", len(shape)))
            for dim in shape:
                fout.write(struct.pack("<Q", dim))

            fout.write(struct.pack("<I", int(tensor.tensor_type)))
            fout.write(struct.pack("<Q", tensor_offsets[i]))

        # 4.4 Pad to alignment
        current_pos = fout.tell()
        alignment = get_field_value(target_reader, "general.alignment") or 32
        padding_needed = (alignment - (current_pos % alignment)) % alignment
        if padding_needed:
            fout.write(b"\x00" * padding_needed)

        # 4.5 Copy tensor data
        print(f"[transplant_mtp] Copying {len(all_tensors)} tensors...")
        for i, tensor in enumerate(all_tensors):
            if i < len(target_reader.tensors):
                offset = target_reader.tensors[i].data_offset
                size = target_on_disk_sizes[i]
                fin = target_fin
            else:
                src_tensor, size = source_tensor_map[tensor.name]
                offset = src_tensor.data_offset
                fin = source_fin

            fin.seek(offset)
            raw_data = fin.read(size)
            fout.write(raw_data)

            if (i + 1) % 50 == 0 or i == len(all_tensors) - 1:
                print(f"[transplant_mtp]   Copied {i + 1}/{len(all_tensors)} tensors")

    # ------------------------------------------------------------------
    # 5. Verify output
    # ------------------------------------------------------------------
    output_size = Path(output_path).stat().st_size
    print(f"\n[transplant_mtp] Output: {output_path}")
    print(f"[transplant_mtp]   Size: {output_size / 1_000_000_000:.2f} GB")
    print(f"[transplant_mtp]   Tensors: {len(all_tensors)}")

    print("\n[transplant_mtp] Validating output...")
    errors = []
    try:
        out_reader = gguf.GGUFReader(output_path)

        out_block_count = get_field_value(out_reader, block_count_key)
        if out_block_count != source_block_count:
            errors.append(f"block_count: expected {source_block_count}, got {out_block_count}")

        out_nextn = get_field_value(out_reader, nextn_key)
        if out_nextn != source_nextn:
            errors.append(f"nextn_predict_layers: expected {source_nextn}, got {out_nextn}")

        out_tensor_names = {t.name for t in out_reader.tensors}
        for tensor in source_extra:
            if tensor.name not in out_tensor_names:
                errors.append(f"Missing tensor: {tensor.name}")

        # Spot-check tensor data integrity
        print("[transplant_mtp]   Spot-checking tensor data integrity...")
        out_tensors = {t.name: t for t in out_reader.tensors}

        for name in ["token_embd.weight"]:
            if name in out_tensors and name in {t.name for t in target_reader.tensors}:
                target_t = next((t for t in target_reader.tensors if t.name == name), None)
                out_t = out_tensors.get(name)
                if target_t and out_t:
                    target_hash = hashlib.sha256(target_t.data.tobytes()).hexdigest()[:16]
                    out_hash = hashlib.sha256(out_t.data.tobytes()).hexdigest()[:16]
                    if target_hash == out_hash:
                        print(f"[transplant_mtp]     {name}: OK ({out_hash})")
                    else:
                        errors.append(f"Data mismatch: {name}")

        if source_extra:
            extra_name = source_extra[0].name
            source_t = source_tensor_map[extra_name][0]
            out_t = out_tensors.get(extra_name)
            if out_t:
                source_hash = hashlib.sha256(source_t.data.tobytes()).hexdigest()[:16]
                out_hash = hashlib.sha256(out_t.data.tobytes()).hexdigest()[:16]
                if source_hash == out_hash:
                    print(f"[transplant_mtp]     {extra_name}: OK ({out_hash})")
                else:
                    errors.append(f"Data mismatch: {extra_name}")

    except Exception as e:
        errors.append(f"Failed to read output: {e}")

    if errors:
        print("\n[transplant_mtp] VALIDATION FAILED:")
        for err in errors:
            print(f"[transplant_mtp]   - {err}")
        sys.exit(1)
    else:
        print("[transplant_mtp]   OK — all checks passed")

    # Clean up
    del target_reader
    del source_reader

    print(f"\n[transplant_mtp] Done. Output: {output_path}")


def main():
    parser = argparse.ArgumentParser(description="Transplant MTP tensors from source GGUF into target GGUF")
    parser.add_argument("--target", required=True, help="Target GGUF (Qwopus Q6_K)")
    parser.add_argument("--source", required=True, help="Source GGUF (MTP Q8_0)")
    parser.add_argument("--output", required=True, help="Output GGUF path")
    args = parser.parse_args()

    if not Path(args.target).exists():
        print(f"[transplant_mtp] ERROR: Target GGUF not found: {args.target}", file=sys.stderr)
        sys.exit(1)

    if not Path(args.source).exists():
        print(f"[transplant_mtp] ERROR: Source GGUF not found: {args.source}", file=sys.stderr)
        sys.exit(1)

    transplant_mtp(args.target, args.source, args.output)


if __name__ == "__main__":
    main()
