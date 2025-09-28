# 📥 HTTP Media Stream Downloader (HLS via Streamlink)

[![MIT License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![GitHub tag](https://img.shields.io/github/tag/IbrahimTouman/VDH_to_Streamlink.svg)](https://github.com/IbrahimTouman/VDH_to_Streamlink/releases)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)
![Shell](https://img.shields.io/badge/shell-bash-blue)  

## 📝 General Description

This is a **robust Bash script for GNU/Linux** that downloads HTTP media streams (HLS) using the
powerful [Streamlink](https://github.com/streamlink/streamlink) CLI tool.  

The script extracts stream parameters primarily from the **“Details” dump** produced by the popular
browser extension [Video DownloadHelper (VDH)](https://www.downloadhelper.net/). These parameters
are then passed to Streamlink, which initiates download immediately. The script can also extract
those same parameters from a provided _cURL command_ if the end-user wishes to do so.  

---

## 🧭 Roadmap

I started this tool because I often struggled to reliably download HLS streams embedded in obscure
websites while using GNU/Linux distros. The [Streamlink](https://github.com/streamlink/streamlink)
CLI tool is great at downloading HLS streams, but not capable at all of capturing them from websites.
On the other hand, the browser extension [Video DownloadHelper (VDH)](https://www.downloadhelper.net/)
is great at capturing HLS streams from websites, but doesn't have the functionalities of a full-fledged
download manager (it is just a browser-extension after all). This script tries to bridge that gap
between the two tools.  

**Goals:**

- ✅ Immediate: save HLS media streams from websites to MP4 or TS files.  
- 🚧 Future: direct browser extension integration, DASH support, and maybe GUI wrapper.  
- ⌛ Ultimate: the dream is to crate a power tool for GNU/Linux community that rivals  
     the popular [Internet Download Manager (IDM)](https://www.internetdownloadmanager.com/),
     which unfortunately does not support  
     GNU/Linux distributions at all!  

---

## ✨ Features

- Full **error and debug logging**, both in the terminal and in automatically generated log files,
  according to end-user's choice.  
- Flexible input sources: The script can read _VDH details dumps_ or _cURL commands_ from either the
  **Clipboard** or from a dedicated **input file**.  
- Prevents accidental overwriting or deleting of any existing file.  
- Sanitizes user-provided filenames for cross-platform safety (MS-Windows & GNU/Linux).  
- A proper file-extension detection is implemented using a **smart solution** (cheap → rigorous →
  fallback): First, a cheap inspection of the provided media URL is carried out in order to see if
  it mentions `.mp4` or `.ts`. Second, if the previous step produces no result, then a rigorous
  **inpsection of the entire m3u8 playlist** is carried out in order to see if the media stream is
  acually made of `mp4` or `ts` segments. Third, if both previous steps produce no result, then the
  fallback `.ts` is used.  
- Output media files are marked by the `.incomplete` suffix until download is complete, and only
  then the suffix is removed safely.  

---

## 📜 Notes

- The script utilizes [Streamlink](https://github.com/streamlink/streamlink), and thus it is
  **bounded by what [Streamlink](https://github.com/streamlink/streamlink) can do**. For example,
  [Streamlink](https://github.com/streamlink/streamlink) considers YouTube videos to be protected
  content, and hence refuses to download them.  
- The script always informs [Streamlink](https://github.com/streamlink/streamlink) to select the
  **best quality available** in the HLS stream for download.  
- The detected file-extension is attached to name of the output media file, overwriting any media
  file-extension the end-user might have provided incorrectly or unnecessarily.  
- The [VDH extension](https://www.downloadhelper.net/) is **gratis** and works across major browsers
  (Chromium, Chrome, Firefox, etc.).  
- [VDH](https://www.downloadhelper.net/) v10.0.198.2 was thoroughly tested and confirmed to reliably
  capture HLS streams and generate _details dump_ with the required parameters, either `#0 main url`
  or (`Media URL`, `accept*`, `user-agent*`, `origin*`, `sec-*`, `connection`).  
- If your version of [VDH](https://www.downloadhelper.net/) produces incomplete _details dump_ which
  misses required headers, then [Streamlink](https://github.com/streamlink/streamlink) may fail to
  download HLS streams from certain websites. However, the good news is that you can skip using the
  [VDH extension](https://www.downloadhelper.net/) altogether. For that to succeed, the script must
  be fed with the other input alternative, which is a _cURL command_ generated via any browser’s
  DevTools (`Inspect (Q)` ─► `Network` tab ─► filter for `m3u8` requests ─► select `Copy as cURL`).
  The script will then happily extract the required stream parameters from the provided _cURL command_
  and pass them to [Streamlink](https://github.com/streamlink/streamlink).  

---

## 📦 Requirements

- `Bash 4.0+` 
- [`Streamlink`](https://github.com/streamlink/streamlink)  
- [`curlconverter`](https://github.com/curlconverter/curlconverter) (through [npm](https://github.com/npm/cli#))  
- [`curl`](https://github.com/curl/curl)  
- [`jq` ](https://github.com/jqlang/jq)  
- [`ffmpeg`](https://github.com/FFmpeg/FFmpeg)  
- [`wl-clipboard`](https://github.com/bugaevc/wl-clipboard) (for Clipboard handling on [Wayland](https://gitlab.freedesktop.org/wayland/wayland))  
- [`xclip`](https://linux.die.net/man/1/xclip) or
  [`xsel`](https://linux.die.net/man/1/xsel) (if you use DE running on X11 session)  

---

## 🧞 How To Use

```text
DEBUG=X bash vdh2streamlink.sh [-h|--help] [-l|--logfile] [-f=|--format=VDH/cURL] \
                    [-c|--clipboard] [-i|--input data.txt] [-o|--output newVideo]

DEBUG=X...........default OFF - disable explicitly by DEBUG=0 - enable by DEBUG=1 or DEBUG=2

-h|--help.........Print this usage message and terminate the program immediately.

-l|--logfile......Optional: If set, a log file will be created in the 'SL_logs/' directory,
                  next to the output media file, and name of the log file will be derived
                  from name of the output media file. Otherwise, logs are written to stderr
                  (fd2) as usual.

-f=|--format=.....Required: The 'VDH' argument means that format of input data matches
                  structure of the data dumped when selecting "Details" in the browser-
                  extension Video DownloadHelper. On the other hand, the 'cURL' argument
                  means that format of input data matches structure of the data dumped
                  when selecting "copy as cURL" in any browser's DevTools.

-c|--clipboard....Required: If set, the input data is read from the Clipboard. This switch
                  is mutually exclusive with -i|--input.

-i|--input........Required: provide a file (e.g., 'data.txt') containing the input data.
                  This option is mutually exclusive with -c|--clipboard.

-o|--output.......Optional: provide a filename without file-extension (e.g., 'newVideo')
                  to be used for the generated output media file. Otherwise, the default
                  filename will be "newVideo_{timestamp}.{ts/mp4}".
```

---

## 🚀 Quick Usage Example

```bash
# Provided that the 'VDHdump.txt' input file contains textual data in "VDH details" format:
DEBUG=1 bash vdh2streamlink.sh --logfile --format=VDH --input VDHdump.txt --output newVideo

# Provided that the 'cURL.txt' input file contains textual data in "cURL command" format:
DEBUG=1 bash vdh2streamlink.sh -l -f=cURL -i cURL.txt -o ~/Downloads/newVideo
```

---

## 🗝️ Installation

Clone this repository, make the script executable, and create input files:  

```bash
git clone https://github.com/IbrahimTouman/VDH_to_Streamlink
cd VDH_to_Streamlink
chmod +x vdh2streamlink.sh

# You can always use these new files to store textual data about different HLS streams
touch VDHdump.txt cURL.txt
```

---

## ⚙️ Logging Inner Workings

Debug and error handling are implemented using separate file descriptors
(`stdout` (`fd1`), `stderr` (`fd2`), `fd3`, see
[Bash redirections](https://www.gnu.org/software/bash/manual/bash.html#Redirections))
with multiplexing handled by
[`tee(1)`](https://www.gnu.org/software/coreutils/manual/html_node/tee-invocation.html).  

```text
1. As a general rule, debug messages are always written to fd3 (wherever
   that goes). Also as a general rule, error messages are always written
   to stderr fd2 (wherever that goes).
2. As an initial state (i.e., set early on in the script), fd3 is redirected
   to stderr (fd2), which in turn writes to the terminal as usual.
3. The fd wiring logic shown in the diagram below (which uses GNU's tee) is
   then applied only if the end-user asks for a log file to be generated.

┌────────────────────────────────────────────────────────────────────────┐
│ ASCII pipeline diagram of fd wiring logic with log file:               │
├────────────────────────────────────────────────────────────────────────┤
│                  ┌─────────────────────┐                               │
│ script’s fd3 ───►│tee's stdin          │                               │
│          ▲       │                     │                               │
│          │       │          tee appends│──► log file                   │
│ xtrace ──┘       │         tee's stdout│──► 1>/dev/null                │
│                  └─────────────────────┘                               │
│                                                                        │
│                                                                        │
│ script’s fd2 ──┬────────────────────────────────────────┬───► terminal │
│                │   ┌─────────────────────┐              ▲              │
│                └──►│tee's stdin          │              │              │
│                    │                     │              │              │
│                    │          tee appends│──► log file  │              │
│                    │         tee's stdout│──────────────┘              │
│                    └─────────────────────┘                             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## ⚖️ License

This work is licensed under the
[MIT license](https://github.com/IbrahimTouman/VDH_to_Streamlink/blob/master/LICENSE)
([OSI reference](https://opensource.org/licenses/MIT)) for details  

---

### 📬 Contact

Ibrahim Touman - ibrahim.touman@gmail.com  
Project Link: https://github.com/IbrahimTouman/VDH_to_Streamlink  
