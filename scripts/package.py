import argparse
import json
import math
import re
import stat
import sys
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit


def excluded_path(path):
    return any(part.startswith(".") or part in ("tmp", "__pycache__") for part in path.parts) or path.suffix in (".pyc", ".pyo")


def icon_dimensions(path):
    if path.suffix.lower() != ".svg":
        raise ValueError(f"{path.name}: this bundle uses SVG icons")
    svg = ET.parse(path).getroot()
    if svg.tag != "{http://www.w3.org/2000/svg}svg":
        raise ValueError(f"{path.name}: expected an SVG root element")
    lengths = [svg.get(key, "") for key in ("width", "height")]
    if all(re.fullmatch(r"\d+(?:\.\d+)?(?:px)?", value) for value in lengths):
        return tuple(float(value.removesuffix("px")) for value in lengths)
    viewbox = svg.get("viewBox", "").replace(",", " ").split()
    if len(viewbox) == 4:
        return tuple(float(value) for value in viewbox[2:])
    raise ValueError(f"{path.name}: expected numeric dimensions or a viewBox")


def bundled_icon(root, value):
    if not isinstance(value, str) or not value.startswith("./assets/"):
        raise ValueError("icons must use ./assets/ paths")
    relative = PurePosixPath(value)
    if ".." in relative.parts or "\\" in value:
        raise ValueError("icon paths must stay inside assets/")
    if excluded_path(relative):
        raise ValueError(f"{value}: icon would be excluded from the bundle")
    path = root.joinpath(*relative.parts)
    for parent in (path, *path.parents):
        if parent == root:
            break
        if parent.is_symlink():
            raise ValueError(f"{value}: symbolic links cannot be bundled")
    if not path.is_file():
        raise ValueError(f"missing icon: {value}")
    if path.stat().st_size > 5 * 1024 * 1024:
        raise ValueError(f"{value}: icon exceeds 5 MiB")
    width, height = icon_dimensions(path)
    if not all(math.isfinite(size) for size in (width, height)) or width != height or width < 48:
        raise ValueError(f"{value}: icon must be square and at least 48 pixels")


def validate_manifest(root):
    manifest = json.loads((root / "plugin.json").read_text())
    if not isinstance(manifest, dict):
        raise ValueError("plugin.json must contain an object")
    for key in ("name", "version"):
        value = manifest.get(key)
        if not isinstance(value, str) or not value.strip() or any(ord(char) < 32 or char in "/\\" for char in value):
            raise ValueError(f"package {key} cannot be used in a ZIP filename")
    extensions = manifest.get("extensions")
    if not isinstance(extensions, dict):
        raise ValueError("extensions must be an object")
    extension = extensions.get("com.openai")
    if not isinstance(extension, dict):
        raise ValueError("extensions.com.openai must be an object")
    interface = extension.get("interface")
    if not isinstance(interface, dict):
        raise ValueError("missing extensions.com.openai.interface")
    for key, limit in (("displayName", 30), ("shortDescription", 30), ("longDescription", 4000), ("developerName", 80)):
        value = interface.get(key)
        if not isinstance(value, str) or not value.strip() or len(value) > limit:
            raise ValueError(f"{key} must contain 1 to {limit} characters")
    if interface.get("category") != "Developer Tools":
        raise ValueError("category must be Developer Tools")
    for key in ("logo", "composerIcon"):
        bundled_icon(root, interface.get(key))
    for key, value in interface.items():
        if key.endswith("URL"):
            if not isinstance(value, str) or len(value) > 1024:
                raise ValueError(f"{key} must be an HTTPS URL of at most 1024 characters")
            url = urlsplit(value)
            if url.scheme != "https" or not url.hostname or url.username or url.password:
                raise ValueError(f"{key} must be an HTTPS URL without credentials")
    for filename in (".claude-plugin/plugin.json", "gemini-extension.json"):
        path = root / filename
        if path.is_file():
            other = json.loads(path.read_text())
            for key in ("name", "version", "description"):
                if manifest.get(key) != other.get(key):
                    raise ValueError(f"{filename}: {key} differs from plugin.json")
    return manifest


def bundle_files(root):
    files = []
    for name in ("plugin.json", "LICENSE", "PRIVACY.md", "SECURITY.md", "skills", "assets"):
        path = root / name
        if path.is_symlink():
            raise ValueError(f"{name}: symbolic links cannot be bundled")
        if name in ("skills", "assets"):
            if not path.is_dir():
                raise ValueError(f"missing directory: {name}")
            paths = sorted(path.rglob("*"))
        else:
            if not path.is_file():
                raise ValueError(f"missing file: {name}")
            paths = [path]
        for entry in paths:
            relative = entry.relative_to(root)
            if excluded_path(relative):
                continue
            if entry.is_symlink():
                raise ValueError(f"{relative}: symbolic links cannot be bundled")
            if entry.is_file():
                files.append(entry)
    if not any(path.relative_to(root).match("skills/*/SKILL.md") for path in files):
        raise ValueError("the bundle must include skills/*/SKILL.md")
    return sorted(files)


def package(root, manifest, files):
    output = root / "tmp" / f"{manifest['name']}-{manifest['version']}.zip"
    output.parent.mkdir(exist_ok=True)
    partial = output.with_suffix(".zip.partial")
    try:
        with zipfile.ZipFile(partial, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path in files:
                info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (1980, 1, 1, 0, 0, 0))
                info.create_system = 3
                info.external_attr = (stat.S_IFREG | stat.S_IMODE(path.stat().st_mode)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes(), compresslevel=9)
        partial.replace(output)
    finally:
        partial.unlink(missing_ok=True)
    return output


def main():
    parser = argparse.ArgumentParser(description="Validate and package the skills-only OpenAI submission.")
    parser.add_argument("--check", action="store_true", help="validate without creating a ZIP")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        manifest = validate_manifest(root)
        files = bundle_files(root)
        if args.check:
            print(f"OpenAI submission metadata and {len(files)} bundled files validated")
        else:
            print(package(root, manifest, files))
    except (OSError, ValueError, ET.ParseError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
