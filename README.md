# HTTP Media Stream Downloader (HLS/DASH via Streamlink)

## 📝 General Description

This is a **robust Bash script for GNU/Linux** that downloads HTTP media streams (HLS/DASH) using the powerful [Streamlink](https://streamlink.github.io/) CLI tool.  

The script is designed to extract the necessary stream parameters primarily from the *details* dump generated when selecting **“Details”** in the popular browser extension [Video DownloadHelper (VDH)](https://www.downloadhelper.net/). These parameters are then passed to Streamlink, and downloading begins immediately.  

- The VDH extension is **gratis** and works well on most browsers (Chromium, Chrome, Firefox, etc.).  
- At least with VDH v10.0.198.2, HTTP media streams are reliably captured, and the generated *details* dump contains all required parameters `Media URL` or `#0 main url` + (`accept*`, `user-agent*`, `origin*`, `sec-*`, `connection`).  

If your version of VDH produces incomplete *details* dump (missing required headers), then Streamlink may fail downloading certain HTTP media streams. However. the script can still operate without using the VDH extension altogether. In that case, the script can alternatively extract the required stream parameters from a `curl` command generated via **“Copy as cURL”** in a browser’s Developer Tools (after filtering for `m3u8` requests).  

This Bash script uses Streamlink, and thus it is bounded by what Streamlink is able to download. For example, Streamlink considers YouTube videos to be protected content, and hence refuses to download them.

---

## ✨ Features

- Full **error and debug logging**, both in the terminal and in automatically generated log files. The end-user chooses to which destination loggin should go (terminal or logfile).  
- Flexible input sources: The script can read *VDH details dumps* or *cURL commands* from either the system's **Clipboard** or from a dedicated **input file**.  
- The script always informs Streamlink to select the **best available quality** for download in the HTTP media stream.  
- **No existing file gets overwritten or deleted**, even if the end-user provides a conflicting name for the output media file.  
- **Cross-platforms is ensured**, name of the output media file provided by the end-user is sanitized by enforcing MS-Windows filename restrictions.  
- A proper file-extension is detected using an **innovative solution (cheap → rigorous → fallback)**: First, a cheap inspection of the provided media URL is carried out in order to see if it mentions `.mp4` or `.ts`. Second, if the previous step produces no result, then a rigorous inpsection of the entire **m3u8 playlist** (fetched via *'curl -fsSL ...'*) is carried out in order to see if the media stream is acually made of `mp4` or `ts` segments. Third, if both previous steps produce no result, then the fallback `.ts` is used. The detected file-extension is then attached to name of the output media file, overwriting any media file-extension the end-user might have provided unnecessarily.  
- Output media files are **labeled by `.incomplete` suffix** as long as they are in process. When the download finishes, the `.incomplete` suffix is removed gracefully without overwriting any existing file.  

---

## 📦 Requirements

- Bash 4.0+  
- [`Streamlink`](https://streamlink.github.io/)  
- [`curlconverter`](https://github.com/curlconverter/curlconverter)  
- [`curl`](https://github.com/curl/curl)  
- [`jq` ](https://github.com/jqlang/jq)  
- [`ffmpeg`](https://github.com/FFmpeg/FFmpeg)  
- `wl-clipboard` (if you use [KDE Plasma](https://kde.org/plasma-desktop/) DE)  
- `xclip` or `xsel` (if you use DE running on X11 session)  

---

## 🧞 How To Use

```text
DEBUG=X bash vdh2streamlink.sh [-h|--help] [-l|--logFile] [-f=|--format=VDH/cURL] \
                    [-c|--clipboard] [-i|--input data.txt] [-o|--output outFile]

DEBUG=X.............default OFF -- disable explicitly by DEBUG=0 -- enable by DEBUG=1 or DEBUG=2

[-h|--help].........Print this usage message and terminate the program immediately.

[-l|--logfile]......Optional: If set, a log file will be created in the 'SL_logs/' directory,
                    next to the output media file, and name of the log file will be derived
                    from name of the output media file. Otherwise, logs are written to stderr
                    (fd2) as usual.

[-f=|--format=].....Required: The 'VDH' argument means that format of the input data (whose
                    source is either the Clipboard or a file) matches structure of the data
                    dumped when selecting "Details" in the popular browser-extension Video
                    DownloadHelper. On the other hand, the 'cURL' argument means that format
                    of the input data matches structure of the data dumped when selecting
                    "copy as cURL" in a browser's Developer Tool (Firefox/Chrome).

[-c|--clipboard]....Required: If set, the input data is read from the Clipboard. This switch
                    is mutually exclusive with [-i|--input] (i.e., only one of them must be
                    provided).

[-i|--input]........Required: provide a file (e.g., 'data.txt') containing the input data.
                    This option is mutually exclusiv. with [-c|--clipboard] (i.e., only one
                    of them must be provided).

[-o|--output].......Optional: provide a filename without file-extension (e.g., 'outFile')
                    to be used for the generated output media file. Otherwise, the default
                    filename will be "output_{timestamp}.{ts/mp4}".
```

---

## 🚀 Quick Usage Example

1. Install dependencies (assuming a GNU/Linux Debian-based distro is used):  
   ```bash
   sudo apt-get install streamlink
   sudo apt-get install curl
   sudo apt-get install jq
   sudo apt-get install npm && npm install --global curlconverter
   ```
2. Execute this command provided that input data is in VDH *details* format:  
   ```bash
   DEBUG=1 bash vdh2streamlink.sh --logfile --format=VDH --input VDHdump.txt --output ~/Downloads/'Never Gonna Give You Up - odysee'
   ```
3. Or execute this command provided that input data is in cURL command format:  
   ```bash
   DEBUG=1 bash vdh2streamlink.sh -l -f=cURL -i cURL.txt -o ~/Downloads/'Never Gonna Give You Up - odysee'
   ```

---

## 🗝️ Installation

Clone this repository and make the script executable:  

```bash
git clone https://github.com/IbrahimTouman/VDH_to_Streamlink
cd VDH_to_Streamlink
chmod +x vdh2streamlink.sh
touch VDHdump.txt cURL.txt
```

---

## 📜 Extras

In case the end-user asks for debug/error messages to be redirected to an automatically generated log-file, then the steps taken to achieve it are as following:  
```text
1. As a general rule, debug messages are always written to file-descriptor-3
   (fd3) (wherever that goes). Also as a general rule, error messages are
   always written to stderr fd2 (wherever that goes).
2. As an initial state (i.e., set early in the script), fd3 is redirected
   to stderr (fd2), which in turn writes to the terminal as usual.
3. The fd wiring logic shown in the diagram below (which uses GNU's tee)
   is applied only if the end-user asks for a log-file to be created.

##########################################################################
# ASCII pipeline diagram of fd wiring logic with log-file:               #
##########################################################################
#                  ┌─────────────────────┐                               #
# script’s fd3 ───►│tee's stdin          │                               #
#          ▲       │                     │                               #
#          │       │           tee writes│──► log-file                   #
# xtrace ──┘       │         tee's stdout│──► 1>/dev/null                #
#                  └─────────────────────┘                               #
#                                                                        #
#                                                                        #
# script’s fd2 ──┬────────────────────────────────────────┬───► terminal #
#                │   ┌─────────────────────┐              ▲              #
#                └──►│tee's stdin          │              │              #
#                    │                     │              │              #
#                    │          tee appends│──► log-file  │              #
#                    │         tee's stdout│──────────────┘              #
#                    └─────────────────────┘                             #
##########################################################################
```

---

## ⚖️ LICENSE

This work is licensed under the MIT license - see the [LICENSE](https://github.com/IbrahimTouman/VDH_to_Streamlink/blob/master/LICENSE) file for details  
