#!/usr/bin/env python3
"""Readonly validation of Polaris2048Fix.app preview versus original backup.

Not an OpenCore parser; does not prove injection or Metal acceleration.
"""
import argparse
import hashlib
import pathlib
import plistlib
import sys


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('preview_folder', type=pathlib.Path)
    parser.add_argument('--pci-path', required=True)
    args = parser.parse_args()
    before = plistlib.loads((args.preview_folder / 'config.original.backup.plist').read_bytes())
    after = plistlib.loads((args.preview_folder / 'config.polaris-preview.plist').read_bytes())
    a = before['DeviceProperties']['Add'][args.pci_path]
    b = after['DeviceProperties']['Add'][args.pci_path]
    assert b['device-id'] == bytes.fromhex('df670000')
    assert len(b['ATY,bin_image']) == 65536
    assert b['ATY,bin_image'][:2] == b'\x55\xaa'
    assert before != after
    for prop in ('ATY,bin_image', 'device-id'):
        a.pop(prop, None)
        b.pop(prop, None)
    assert a == b, 'Other GPU properties changed'
    del before['DeviceProperties']['Add'][args.pci_path]
    del after['DeviceProperties']['Add'][args.pci_path]
    assert before == after, 'Unrelated OpenCore properties changed'
    print('OK: source backup and candidate differ only by the two targeted properties.')
    print('ATY,bin_image SHA256:', sha((args.preview_folder / 'config.polaris-preview.plist').read_bytes()))
    print('This does NOT establish boot compatibility or Metal acceleration.')


if __name__ == '__main__':
    try: main()
    except Exception as exc:
        print('FAIL:', exc, file=sys.stderr)
        raise SystemExit(1)
