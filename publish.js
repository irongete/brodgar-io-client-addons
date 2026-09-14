#!/usr/bin/env node
// publish -- zips one addon folder of this repo and uploads it to the brodgar.io hub.
//
//   npm run publish -- <addon> [--version X.Y.Z]
//   node publish.js <addon> [--version X.Y.Z]
//
// Without --version the manifest's X.Y.Z becomes X.Y.(Z+1). Either way the version is written into
// manifest.json before packing, because the hub reads the version from the manifest inside the zip,
// and it is put back the way it was if the upload fails. The package is the shape the client installs:
// every entry under <id>/, so <id>/manifest.json, <id>/main.lua, ...
//
// The token is BRODGAR_TOKEN, set in the .env file beside this script (git ignores it) or in the
// environment, or passed as --token; create one at https://brodgar.io/addons/settings. BRODGAR_HUB,
// set the same way, points the tool at another hub.

import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { crc32, deflateRawSync } from "node:zlib";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO_ROOT = path.dirname(fileURLToPath(import.meta.url));
const ENV_FILE = path.join(REPO_ROOT, ".env");
if (existsSync(ENV_FILE)) {
    process.loadEnvFile(ENV_FILE); // a variable the environment already sets wins over the file
}
const HUB_URL = (process.env.BRODGAR_HUB || "https://brodgar.io/addons/api").replace(/\/+$/, "");

// MAJOR.MINOR.PATCH with an optional pre-release, which is what the hub orders.
const VERSION_PATTERN = /^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/;
// Files that are never part of a package.
const SKIPPED_NAMES = new Set(["luac.out", ".DS_Store", "Thumbs.db", "desktop.ini", ".git", "node_modules"]);

const USAGE = `usage: publish <addon> [--version X.Y.Z] [--token bio_...]

Zips <addon>/ and uploads it to ${HUB_URL}. Without --version the manifest's
X.Y.Z becomes X.Y.(Z+1); the version is written to manifest.json before packing and put back
if the upload fails.

Token: BRODGAR_TOKEN=bio_... in ${ENV_FILE} (https://brodgar.io/addons/settings), or --token.`;

function fail(message) {
    throw new Error(message);
}

// ---------------------------------------------------------------- arguments

function parseArguments(argv) {
    const options = { addon: null, version: null, token: null, help: false };
    for (let index = 0; index < argv.length; index++) {
        const argument = argv[index];
        if (argument === "--help" || argument === "-h") {
            options.help = true;
        } else if (argument === "--version") {
            options.version = argv[++index];
            if (options.version === undefined) {
                fail("--version needs a value, X.Y.Z");
            }
        } else if (argument.startsWith("--version=")) {
            options.version = argument.slice("--version=".length);
        } else if (argument === "--token") {
            options.token = argv[++index];
            if (options.token === undefined) {
                fail("--token needs a value");
            }
        } else if (argument.startsWith("--token=")) {
            options.token = argument.slice("--token=".length);
        } else if (argument.startsWith("-")) {
            fail(`unknown option ${argument}\n${USAGE}`);
        } else if (options.addon === null) {
            options.addon = argument;
        } else if (options.version === null && /^\d+\.\d+\.\d+/.test(argument)) {
            // `npm run publish gob-cache-map 1.2.3`: npm keeps --flags for itself unless they come
            // after `--`, so a bare version after the addon is taken as one too.
            options.version = argument;
        } else {
            fail(`unexpected argument ${argument}\n${USAGE}`);
        }
    }
    return options;
}

// The addon is a folder: a path as typed, or a folder of this repo by name.
function resolveAddonDirectory(addon) {
    const asTyped = path.resolve(addon);
    if (existsSync(asTyped) && statSync(asTyped).isDirectory()) {
        return asTyped;
    }
    const inRepo = path.join(REPO_ROOT, addon);
    if (existsSync(inRepo) && statSync(inRepo).isDirectory()) {
        return inRepo;
    }
    fail(`no addon folder ${addon} (looked at ${[...new Set([asTyped, inRepo])].join(" and ")})`);
}

function resolveToken(optionToken) {
    if (optionToken) {
        return optionToken;
    }
    if (process.env.BRODGAR_TOKEN) {
        return process.env.BRODGAR_TOKEN;
    }
    fail(`no token: put BRODGAR_TOKEN=bio_... in ${ENV_FILE}, or pass --token\n`
        + "(create one at https://brodgar.io/addons/settings)");
}

// ---------------------------------------------------------------- the manifest

function readManifest(addonDirectory) {
    const manifestPath = path.join(addonDirectory, "manifest.json");
    if (!existsSync(manifestPath)) {
        fail(`${manifestPath} does not exist`);
    }
    const text = readFileSync(manifestPath, "utf8");
    let manifest;
    try {
        manifest = JSON.parse(text);
    } catch (error) {
        fail(`${manifestPath}: ${error.message}`);
    }
    const id = path.basename(addonDirectory);
    if (manifest.id !== id) {
        fail(`${manifestPath} says id "${manifest.id}" but the folder is ${id}`);
    }
    if (!Array.isArray(manifest.files) || manifest.files.length === 0) {
        fail(`${manifestPath} has no "files"`);
    }
    for (const file of manifest.files) {
        if (!existsSync(path.join(addonDirectory, file))) {
            fail(`${manifestPath} lists ${file}, which is not in the folder`);
        }
    }
    return { manifestPath, text, manifest };
}

function chooseVersion(requested, manifest) {
    if (requested !== null) {
        if (!VERSION_PATTERN.test(requested)) {
            fail(`version ${requested} is not X.Y.Z`);
        }
        return requested;
    }
    const current = manifest.version;
    if (typeof current !== "string") {
        fail("manifest.json has no version to bump; pass --version X.Y.Z");
    }
    const parts = /^(\d+)\.(\d+)\.(\d+)$/.exec(current);
    if (parts === null) {
        fail(`manifest.json's version ${current} is not X.Y.Z, so it cannot be bumped; pass --version`);
    }
    return `${parts[1]}.${parts[2]}.${Number(parts[3]) + 1}`;
}

// The version swapped inside the text itself, so the file keeps its own layout.
function withVersion(manifestText, version) {
    const versionField = /("version"\s*:\s*")([^"]*)(")/;
    if (!versionField.test(manifestText)) {
        fail("manifest.json has no \"version\" field; add one");
    }
    const updated = manifestText.replace(versionField, (match, before, oldVersion, after) => before + version + after);
    if (JSON.parse(updated).version !== version) {
        fail("could not write the version into manifest.json");
    }
    return updated;
}

// ---------------------------------------------------------------- the package

// Every file under the folder, sorted, named <id>/<path> with forward slashes.
function collectFiles(directory, namePrefix, files = []) {
    for (const entryName of readdirSync(directory).sort()) {
        if (SKIPPED_NAMES.has(entryName)) {
            continue;
        }
        const fullPath = path.join(directory, entryName);
        const info = statSync(fullPath);
        if (info.isDirectory()) {
            collectFiles(fullPath, namePrefix + entryName + "/", files);
        } else if (info.isFile()) {
            files.push({ name: namePrefix + entryName, data: readFileSync(fullPath), modified: info.mtime });
        }
    }
    return files;
}

function dosDateTime(date) {
    const year = Math.max(date.getFullYear(), 1980);
    const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
    const day = ((year - 1980) << 9) | ((date.getMonth() + 1) << 5) | date.getDate();
    return { time, day };
}

// A plain zip: one local header + data per file, then the central directory and its end record.
// Sizes and CRCs are known before each header is written, so nothing needs a data descriptor.
function buildZip(files) {
    const localParts = [];
    const centralParts = [];
    let offset = 0;
    for (const file of files) {
        const nameBytes = Buffer.from(file.name, "utf8");
        const deflated = deflateRawSync(file.data, { level: 9 });
        const useDeflate = deflated.length < file.data.length;
        const method = useDeflate ? 8 : 0;
        const payload = useDeflate ? deflated : file.data;
        const checksum = crc32(file.data);
        const { time, day } = dosDateTime(file.modified);

        const localHeader = Buffer.alloc(30);
        localHeader.writeUInt32LE(0x04034b50, 0);
        localHeader.writeUInt16LE(20, 4); // version needed to extract: 2.0
        localHeader.writeUInt16LE(0x0800, 6); // flags: names are UTF-8
        localHeader.writeUInt16LE(method, 8);
        localHeader.writeUInt16LE(time, 10);
        localHeader.writeUInt16LE(day, 12);
        localHeader.writeUInt32LE(checksum, 14);
        localHeader.writeUInt32LE(payload.length, 18);
        localHeader.writeUInt32LE(file.data.length, 22);
        localHeader.writeUInt16LE(nameBytes.length, 26);
        localHeader.writeUInt16LE(0, 28); // extra field length

        const centralHeader = Buffer.alloc(46);
        centralHeader.writeUInt32LE(0x02014b50, 0);
        centralHeader.writeUInt16LE(20, 4); // version made by: 2.0, MS-DOS attributes
        centralHeader.writeUInt16LE(20, 6); // version needed to extract
        centralHeader.writeUInt16LE(0x0800, 8);
        centralHeader.writeUInt16LE(method, 10);
        centralHeader.writeUInt16LE(time, 12);
        centralHeader.writeUInt16LE(day, 14);
        centralHeader.writeUInt32LE(checksum, 16);
        centralHeader.writeUInt32LE(payload.length, 20);
        centralHeader.writeUInt32LE(file.data.length, 24);
        centralHeader.writeUInt16LE(nameBytes.length, 28);
        centralHeader.writeUInt16LE(0, 30); // extra field length
        centralHeader.writeUInt16LE(0, 32); // comment length
        centralHeader.writeUInt16LE(0, 34); // disk number
        centralHeader.writeUInt16LE(0, 36); // internal attributes
        centralHeader.writeUInt32LE(0, 38); // external attributes
        centralHeader.writeUInt32LE(offset, 42); // where the local header is

        localParts.push(localHeader, nameBytes, payload);
        centralParts.push(centralHeader, nameBytes);
        offset += localHeader.length + nameBytes.length + payload.length;
    }
    const centralDirectory = Buffer.concat(centralParts);
    const endRecord = Buffer.alloc(22);
    endRecord.writeUInt32LE(0x06054b50, 0);
    endRecord.writeUInt16LE(0, 4); // this disk
    endRecord.writeUInt16LE(0, 6); // the disk the central directory starts on
    endRecord.writeUInt16LE(files.length, 8);
    endRecord.writeUInt16LE(files.length, 10);
    endRecord.writeUInt32LE(centralDirectory.length, 12);
    endRecord.writeUInt32LE(offset, 16);
    endRecord.writeUInt16LE(0, 20); // comment length
    return Buffer.concat([...localParts, centralDirectory, endRecord]);
}

function formatSize(bytes) {
    return bytes < 1024 ? `${bytes} B` : `${(bytes / 1024).toFixed(1)} KB`;
}

// ---------------------------------------------------------------- the hub

async function callHub(token, route, contentType, body) {
    let response;
    try {
        response = await fetch(HUB_URL + route, {
            method: "POST",
            headers: { Authorization: `Bearer ${token}`, "Content-Type": contentType, Accept: "application/json" },
            body,
        });
    } catch (error) {
        const cause = error.cause ? ` (${error.cause.message})` : "";
        fail(`could not reach ${HUB_URL}: ${error.message}${cause}`);
    }
    const text = await response.text();
    let json = null;
    try {
        json = JSON.parse(text);
    } catch {
        // not JSON: the text is the message
    }
    return { status: response.status, ok: response.ok, json, text };
}

function describeError(response) {
    let message = response.text.trim() || "(empty response)";
    if (response.json !== null && typeof response.json === "object") {
        const named = response.json.error ?? response.json.message ?? response.json.detail;
        if (named !== undefined) {
            message = typeof named === "string" ? named : JSON.stringify(named);
        }
    }
    return `HTTP ${response.status}: ${message}`;
}

// The addon is created once; a 409 says it is there already.
async function ensureAddonOnHub(token, manifest) {
    const listing = {
        id: manifest.id,
        name: typeof manifest.name === "string" ? manifest.name : manifest.id,
        summary: typeof manifest.description === "string" ? manifest.description : "",
    };
    const response = await callHub(token, "/addons", "application/json", JSON.stringify(listing));
    if (response.status === 409) {
        console.log(`${manifest.id} is on the hub already`);
    } else if (response.ok) {
        console.log(`created ${manifest.id} on the hub`);
    } else {
        fail(`could not create ${manifest.id} on the hub -- ${describeError(response)}`);
    }
}

async function uploadVersion(token, id, version, zipBytes) {
    const response = await callHub(token, `/addons/${encodeURIComponent(id)}/versions`, "application/zip", zipBytes);
    if (!response.ok) {
        const hint = response.status === 409 ? " (that version is published already; pass --version)" : "";
        fail(`could not publish ${id} ${version} -- ${describeError(response)}${hint}`);
    }
    return response.json !== null && typeof response.json === "object" ? response.json : {};
}

// ---------------------------------------------------------------- main

async function main() {
    const options = parseArguments(process.argv.slice(2));
    if (options.help || options.addon === null) {
        console.log(USAGE);
        process.exitCode = options.help ? 0 : 1;
        return;
    }
    const token = resolveToken(options.token);
    const addonDirectory = resolveAddonDirectory(options.addon);
    const { manifestPath, text: originalText, manifest } = readManifest(addonDirectory);
    const id = manifest.id;
    const version = chooseVersion(options.version, manifest);
    const updatedText = withVersion(originalText, version);

    await ensureAddonOnHub(token, manifest);

    // From here the manifest on disk carries the new version; it goes back if anything fails.
    writeFileSync(manifestPath, updatedText);
    let published = false;
    try {
        const files = collectFiles(addonDirectory, id + "/");
        const zipBytes = buildZip(files);
        const sha256 = createHash("sha256").update(zipBytes).digest("hex");
        console.log(`${id} ${manifest.version} -> ${version}: ${files.length} files, ${formatSize(zipBytes.length)} zipped`);

        const result = await uploadVersion(token, id, version, zipBytes);
        published = true;
        console.log(`published ${id} ${result.version ?? version}`);
        if (result.package_url) {
            console.log(`  ${result.package_url}`);
        }
        if (typeof result.sha256 === "string" && result.sha256.toLowerCase() !== sha256) {
            console.log(`  warning: the hub stored sha256 ${result.sha256}, the upload was ${sha256}`);
        }
    } finally {
        if (!published) {
            writeFileSync(manifestPath, originalText);
        }
    }
}

main().catch((error) => {
    console.error(`publish: ${error.message}`);
    process.exit(1);
});
