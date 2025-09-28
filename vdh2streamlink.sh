#!/usr/bin/env bash


# instructs Bash to immediately halt excution if any command returns a non-zero exit status
set -o errexit

# any reference to any unset variable (with the exceptions of $* and $@) is an error
set -o nounset

# prevents errors in a pipeline from being masked. If any command in a pipeline
# fails, that error-code will be used as the return code of the whole pipeline
set -o pipefail


how_to_use()
{
    cat <<EOF

Usage:
    DEBUG=X $0 [-h|--help] [-l|--logfile] [-f=|--format=VDH/cURL] [-c|--clipboard] [-i|--input data.txt] [-o|--output newVideo]

    DEBUG=X...........default OFF - disable explicitly by DEBUG=0 - enable by DEBUG=1 or DEBUG=2

    -h|--help.........Print this usage message and terminate the program immediately.

    -l|--logfile......Optional: If set, a log file will be created in the 'SL_logs/' directory, next to the output media file,
                      and name of the log file will be derived from name of the output media file. Otherwise, logs are written
                      to stderr (fd2) as usual.

    -f=|--format=.....Required: The 'VDH' argument means that format of input data matches structure of the data dumped when
                      selecting "Details" in the browser-extension Video-DownloadHelper (VDH). On the other hand, the 'cURL'
                      argument means that format of input data matches structure of the data dumped when selecting "copy as
                      cURL" in any browser's DevTools.

    -c|--clipboard....Required: If set, input data is read from the Clipboard. This switch is mutually exclusive with -i|--input.

    -i|--input........Required: provide a file (e.g., 'data.txt') containing input data. This option is mutually exclusive with
                      -c|--clipboard.

    -o|--output.......Optional: provide a filename without file-extension (e.g., 'newVideo') to be used for the generated output
                      media file. Otherwise, the default filename will be "newVideo_{timestamp}.{ts/mp4}".
EOF
}

die()
{
    local msg="${1:-"unspecified error!"}"
    local show_usage="${2:-}"  # pass "--usage" to trigger

    # the message is first wrapped in a red ANSI color "\e[0;31m...\e[0m", and then redirected to stderr fd2 (wherever that goes)
    # using "\e[0;31m...\e[0m" assumes ANSI — works 99% of the time, but you could detect 'tput setaf 1' for more portability
    printf '%b\n' "The script exited with error-code 1 because: \e[0;31m$msg\e[0m" >&2

    [[ "$show_usage" == "--usage" ]] && how_to_use >&2  # redirected to stderr fd2 (wherever that goes)

    exit 1  # this way, we immediately break out of the entire script no matter what (1 indicates failure)
}

# --- debugging facility ---
exec 3>&2  # fd3 goes through stderr (fd2) from now on, until further notice!
DEBUG="${DEBUG:-0}"  # default OFF
log_debug()
{
    case "$DEBUG" in
        0) ;; # print nothing..
        1|2) printf '%b\n' "$@" >&3 ;;  # redirected to fd3 (wherever that goes)
        *) die "unrecognized DEBUG=$DEBUG, please stick to DEBUG=0, DEBUG=1, or DEBUG=2" --usage ;;
    esac
}

have() { command -v "$1" 1>/dev/null 2>&1; } # helper function



read_Clipboard=false
read_inputDataFile=false
userDefined_outputFile=false
generate_logFile=false
inputFormat=""
inputDataFile=""
outputFile=""
logFile=""

# --- parse options ---
while [[ "$#" -gt 0 ]]; do
    case "${1,,}" in
        -h|--help)
            how_to_use
            exit 0
            ;;

        -f=*|--format=*)
            [[ -z "$inputFormat" ]] || die "the -f=|--format= option may not be repeated" --usage
            inputFormat="${1#*=}"
            if [[ "${inputFormat,,}" != vdh && "${inputFormat,,}" != curl ]]; then  # ${inputFormat,,} → lowercase
                die "unrecognized argument '$inputFormat' given for option -f=|--format=" --usage
            fi
            shift
            ;;

        -c|--clipboard)
            [[ "$read_Clipboard" == false ]]     || die "the -c|--clipboard switch may not be repeated" --usage
            [[ "$read_inputDataFile" == false ]] || die "-c|--clipboard is mutually exclusive with -i|--input" --usage
            read_Clipboard=true
            shift
            ;;

        -i|--input)
            [[ "$read_inputDataFile" == false ]] || die "the -i|--input option may not be repeated" --usage
            [[ "$read_Clipboard" == false ]]     || die "-i|--input is mutually exclusive with -c|--clipboard" --usage
            read_inputDataFile=true;
            inputDataFile="$2"
            shift 2
            ;;

        -o|--output)
            [[ "$userDefined_outputFile" == false ]] || die "the -o|--output option may not be repeated" --usage
            userDefined_outputFile=true
            outputFile="$2"
            shift 2
            ;;

        -l|--logfile)
            [[ "$generate_logFile" == false ]] || die "the -l|--logfile switch may not be repeated" --usage
            generate_logFile=true
            shift
            ;;

        -*)
            die "unknown option '$1'" --usage
            ;;

        *)
            die "positional arguments are not accepted '$1'" --usage
            ;;
    esac
done


if [[ "$generate_logFile" == false ]]; then
    # the destination to which stderr (fd2) points is wrapped in a yellow ANSI color "\e[0;33m...\e[0m"
    printf '%b\n\n' "Debug messages will be written to '/proc/$$/fd/3' (which points to \e[0;33m'$(readlink /proc/$$/fd/3)'\e[0m)"
fi

expand_tilde_in_path()
{
    local path="$1"

    case "$path" in
        "~")   echo "$HOME" ;;
        "~"/*) echo "$HOME/${path#*~/}" ;;
        "~"*)  die "tilde expansion for other users is not allowed '$path'" ;;
        *)     echo "$path" ;;
    esac
}

# We want cross-platform compatible filenames, so we strip or replace anything that MS-Windows disallows
sanitize_filename()
{
    local directory=""
    local base=""

    directory=$(dirname -- "$1")
    base=$(basename -- "$1")

    # 1) inspect first if the provided directory exists or not
    [[ -d "$directory" ]] || die "the provided directory '$directory' does not exist"

    # MS-Windows disallows these characters in filenames \ / : * ? " < > |
    # Leading/trailing spaces and dots are problematic, also reserved names like CON, NUL, PRN, etc.

    # 2) replace forbidden characters
    # 3) remove trailing spaces/dots
    base=$(printf '%s\n' "$base" | sed -E 's#[:\\*"?<>|]#-#g; s/[ .]+$//') # this is GNU sed variant (uses -E for +)

    # 4) Handle reserved MS-Windows names (case-insensitive)
    case "${base^^}" in
        CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9]) base="_${base}" ;;
    esac

    # 5) if result is empty (e.g., provided filename was only dots/spaces), fall back to a default name
    if [[ -z "$base" ]]; then
        base="newVideo_$(date +'%Y-%m-%d_%H-%M-%S')"
    fi

    # 6) recombine directory + sanitized basename
    if [[ "$directory" == "." ]]; then
        echo "$base"
    else
        echo "$directory/$base"
    fi
}

if [[ "$userDefined_outputFile" == true ]]; then
    outputFile=$(expand_tilde_in_path "$outputFile")
    outputFile=$(sanitize_filename "$outputFile")  # make the filename compatible with MS-Windows

    if [[ "$generate_logFile" == true ]]; then
        logFile_base=""
        logFile_directory=""

        logFile_base=$(basename -- "$outputFile")
        logFile_directory="$(dirname -- "$outputFile")/SL_logs"
        [[ -d "$logFile_directory" ]] || mkdir "$logFile_directory"
        logFile_base=$(echo "$logFile_base" | sed -r 's/[ ]+/_/g')  # replace every whitespace with underscore
        logFile="${logFile_directory}/${logFile_base}_${RANDOM}.log"  # $RANDOM gives an integer between 0 and 32767
    fi
else
    # generate default name for the output media file because the end-user did not provide a custom one
    outputFile=$(printf '%s_%s' "newVideo" "$(date +'%Y-%m-%d_%H-%M-%S')")

    if [[ "$generate_logFile" == true ]]; then
        logFile_directory="./SL_logs"
        [[ -d "$logFile_directory" ]] || mkdir "$logFile_directory"
        logFile="${logFile_directory}/${outputFile}_${RANDOM}.log"  # $RANDOM gives an integer between 0 and 32767
    fi
fi

if [[ -n "$logFile" ]]; then
    # logfile name is wrapped in a yellow ANSI color "\e[0;33m...\e[0m"
    printf '%b\n\n' "Both debug and error messages will be written to the log file \e[0;33m'$logFile'\e[0m"

    # ASCII pipeline diagram of fd wiring, and further explanation:         #
     #######################################################################
    #                  ┌─────────────────────┐                              #
    # script’s fd3 ───►│tee's stdin          │                              #
    #          ▲       │                     │                              #
    #          │       │          tee appends│──► log file                  #
    # xtrace ──┘       │         tee's stdout│──► 1>/dev/null               #
    #                  └─────────────────────┘                              #
    #                                                                       #
    #                                                                       #
    # script’s fd2 ──┬────────────────────────────────────────┬──► terminal #
    #                │   ┌─────────────────────┐              ▲             #
    #                └──►│tee's stdin          │              │             #
    #                    │                     │              │             #
    #                    │          tee appends│──► log file  │             #
    #                    │         tee's stdout│──────────────┘             #
    #                    └─────────────────────┘                            #
     #######################################################################
    # Step 1 — initial state (assumes some redirections exist):             #
    #   script's stdout (fd1) ──► terminal                                  #
    #   script's stderr (fd2) ──► terminal                                  #
    #   script's fd3 ───────────► fd2                                       #
    #                                                                       #
    # Step 2 — after: exec 3> >(tee "$logFile" 1>/dev/null)                 #
    #   >(...) process substitution runs tee inside it.                     #
    #   fd3 in the script points to tee’s stdin.                            #
    #   inside tee:                                                         #
    #       - copies stdin into log file, using --append                    #
    #       - suppresses its normal stdout using 1>/dev/null                #
    #                                                                       #
    # Step 3 — after: BASH_XTRACEFD=3                                       #
    #   -x trace output also flows into fd3.                                #
    #                                                                       #
    # Step 4 — after: exec 2> >(tee -a "$logFile" 1>&2)                     #
    #   - exec 2> … spawns another tee, which appends                       #
    #     to the same log file and forwards stderr back to                  #
    #     the terminal (1>&2).                                              #
    #   - No recursion, we’re just forking stderr (fd2) into an             #
    #     extra consumer (tee), not feeding it back into itself.            #
     #######################################################################
    exec 3> >(tee --append "$logFile" 1>/dev/null)  # fd3 (for debug & xtrace) → tee → logfile only
    BASH_XTRACEFD=3                                 # debug trace from 'set -x' also goes to fd3
    exec 2> >(tee --append "$logFile" 1>&2)         # fd2 (for errors) → tee → logfile and terminal
fi

read_from_Clipboard()
{
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        # Wayland session
        if { have wl-paste; }; then
            wl-paste || die "we could not read the Clipboard using 'wl-paste'"
        else
            die "Wayland session was detected, but 'wl-paste' (from the 'wl-clipboard' package) is missing"
        fi
    elif [[ -n "$DISPLAY" ]]; then
        # X11 session (possibly via XWayland fallback)
        if { have xclip; }; then
            xclip -selection clipboard -o || die "we could not read the Clipboard using 'xclip'"
        elif { have xsel; }; then
            xsel --clipboard --output || die "we could not read the Clipboard using 'xsel'"
        else
            die "X11 session was detected, but neither 'xclip' nor 'xsel' is installed."
        fi
    else
        die "we could not determine the graphical session, so we cannot determine how to read the Clipboard"
    fi
}

# --- load input data ---
inputData=""
if [[ "$read_Clipboard" == true ]]; then
    inputData="$(read_from_Clipboard)"
elif [[ "$read_inputDataFile" == true ]]; then
    [[ -r "$inputDataFile" ]] || die "the provided input data file '$inputDataFile' does not exist, or unreadable"

    if { file --brief "$inputDataFile" | grep --quiet -i -e "ascii text" -e "UTF-8 text"; }; then
        log_debug "The provided input data file '$inputDataFile' has the correct content type ($(file -b "$inputDataFile"))\n"
    else
        die "the provided input data file '$inputDataFile' has incorrect content type (neither ASCII nor UTF-8 text)"
    fi

    inputData="$(cat -- "$inputDataFile")"
else
    die "the -c|--clipboard switch and -i|--input option cannot be both omitted" --usage
fi

convert_VDH_to_cURL()
{
    VDH_details_dump="$1"
    local title=""
    local page_URL=""
    local thumbnail=""
    local type=""
    local duration=""
    local media_url=""
    local main_url=""
    local URL=""
    local headers=()

    local key=""; local value=""
    while IFS= read -r line; do
        # extract Title, Type, Duration, Media URL, and the headers (lines have tab separators: key<TAB>value)
        if [[ "$line" == *$'\t'* ]]; then
            key="${line%%$'\t'*}"
            value="${line#*$'\t'}"
            case "${key,,}" in  # ${key,,} → lowercase
                title*) title="${line#Title$'\t'}" ;;
                page\ url*) page_URL="${line#Page URL$'\t'}" ;;
                thumbnail*) thumbnail="${line#Thumbnail$'\t'}" ;;
                type*) type="${line#Type$'\t'}" ;;
                duration*) duration="${line#Duration$'\t'}" ;;
                media\ url*) media_url="${line#Media URL$'\t'}" ;;
                \#0\ main\ url*) main_url="${line#\#0 main url$'\t'}" ;;
                accept*|user-agent*|origin*|sec-*|connection*) headers+=("$key" "$value") ;;
            esac
        fi
    done <<<"$VDH_details_dump"

    if [[ -n "$title" || -n "$page_URL" || -n "$thumbnail" || -n "$type" || -n "$duration" ]]; then
        log_debug "From the VDH details dump, we infer the following basic information about the media stream:"
        [[ -n "$title" ]]     && log_debug "  [Title]     [$title]";
        [[ -n "$page_URL" ]]  && log_debug "  [Page URL]  [${page_URL%% *}]";
        [[ -n "$thumbnail" ]] && log_debug "  [Thumbnail] [$thumbnail]";
        [[ -n "$type" ]]      && log_debug "  [Type]      [$type]";
        [[ -n "$duration" ]]  && log_debug "  [Duration]  [$(date -u -d "@$duration" +"%H:%M:%S")]";
        log_debug ""  # print newline
    fi

    # if both 'Media URL' and '#0 main url' parameters exist (which normally should not happen), then prefer 'Media URL'
    [[ -n "$main_url" ]]  && URL="$main_url"
    [[ -n "$media_url" ]] && URL="$media_url"
    [[ -z "$URL" ]] && die "the VDH details dump is ill-formed or contains neither 'Media URL' nor '#0 main url'"

    # construct a cURL command (append headers if they exist), and then echo it
    printf '%s' "curl '$URL'"
    if (( "${#headers[@]}" >= 2 )); then
        printf '%s\n' " \\"
        for ((i=0; i<${#headers[@]}-2; i+=2)); do
            printf '%s %s\n' "  -H" "'${headers[i]}: ${headers[i+1]}' \\"
        done
        printf '%s %s' "  -H" "'${headers[${#headers[@]}-2]}: ${headers[${#headers[@]}-1]}'"
    fi
    printf '\n'
}

cURLcommand=""
if [[ "${inputFormat,,}" == vdh ]]; then  # ${inputFormat,,} → lowercase
    log_debug "The following is your input data (whose format is supposed to conform to VDH details dump):\n$inputData\n"
    cURLcommand="$(convert_VDH_to_cURL "$inputData")"
    log_debug "The following is the cURL command we managed to construct based on your VDH details dump:\n$cURLcommand\n"
elif [[ "${inputFormat,,}" == curl ]]; then  # ${inputFormat,,} → lowercase
    log_debug "The following is your input data (whose format is supposed to conform to cURL command):\n$inputData\n"
    cURLcommand="$inputData"
else
    die "the -f=|--format= option cannot be omitted" --usage
fi


# convert formats from cURL command to JSON dataset using 'curlconverter'
have curlconverter || die "the 'curlconverter' package (from 'npm') is missing, please install it first"
# "tr -d '\r'" removes \r characters from CRLF sequences (some browsers or Clipboard tools use
# MS-Windows line endings). This avoids jq/curlconverter choking on the undesired \r character
if { JSONdataset="$(printf '%s' "$cURLcommand" | tr -d '\r' | curlconverter --language json -)"; }; then
    log_debug "The following is the JSON representaion of your cURL command:\n$JSONdataset\n"
else
    die "'curlconverter' rejected the structure of your cURL command"
fi


# get media URL (prefer '.raw_url', then the fallback '.url')
have jq || die "the 'jq' package is missing, please install it first"
URL=""
URL="$(echo "$JSONdataset" | jq -r '.raw_url // .url // empty')"
[[ -n "$URL" ]] || die "both 'url' and 'raw_url' parameters are missing from the JSON dataset"

# --- Let's build the headers array "--http-header key=value" ---
# IMPORTANT: do NOT embed inner quotation marks (single or double) anywhere in the headers array.
# keep "--http-header" and its corresponding "key=value" as separate array elements.
# The following is an optional jq filter to drop some headers the server might not need:
# "select(.key | test("^(Connection|Sec-Fetch|sec-ch-ua)"; "i") | not)"

kv_pairs=""
kv_pairs="$(echo "$JSONdataset" | jq -r '.headers // {} | to_entries[] | "\(.key)=\(.value)"')"
[[ -n "$kv_pairs" ]] || log_debug "By the way, the JSON dataset contains no 'headers' parameter\n"

# build Streamlink headers arguments needed for downloading the given media stream
SL_headersArgs=()
if [[ -n "$kv_pairs" ]]; then
    while read -r kv; do
        # $kv is "key=value" → transform to: "--http-header" "key=value"
        SL_headersArgs+=( "--http-header" "$kv" )
    done <<<"$kv_pairs"
fi

if (( "${#SL_headersArgs[@]}" >= 2 )); then
    log_debug "The headers which will be passed to Streamlink:"
    for ((i=0; i<${#SL_headersArgs[@]}; i+=2)); do
        log_debug "  [${SL_headersArgs[i]}] [${SL_headersArgs[i+1]}]";
    done
fi
log_debug "The URL which will be passed to Streamlink:\n  [$URL]\n"


# --- output file-extension detection, a "cheap" solution ---
# check the URL (if it ends with '.ts' or '.mp4')
# return '.mp4' extension if the URL mentions '.mp4' anywhere
# return '.ts' extension if the URL mentions '.ts' anywhere
# otherwise, return empty string so that we continue to the next "rigorous" solution
derive_extension_from_URL()
{
  case "$URL" in
    *.mp4*) echo "mp4" ;;
    *.ts*)  echo "ts"  ;;
    *)      echo ""    ;;  # we return empty-handed from this "cheap" method
  esac
}

# --- output file-extension detection, a "rigorous" solution ---
# We ask Streamlink for the resolved stream URL, and then we feed it to 'curl -fsSL' together
# with the appropiate headers in order to fetch the entire m3u8 playlist. We then inspect the
# m3u8 playlist (that Streamlink actually uses during download) to tell fMP4 (.m4s / EXT-X-MAP
# … .mp4) from MPEG-2 TS (.ts), which is definitely more rigorous than just looking at the media
# URL like we did in the previous "cheap" method.
derive_extension_from_playlist()
{
    local stream_URL=""
    local m3u8_playlist=""
    local curl_headersArgs=()

    if { stream_URL="$(streamlink --stream-url "${SL_headersArgs[@]}" "$URL" best 2>/dev/null)"; } ; then
        log_debug "Stream URL (fetched via 'streamlink --stream-url'):\n  [$stream_URL]\n"
    else
        echo ""; return  # we return empty-handed from this "rigorous" method
    fi

    # build curl headers arguments for probing m3u8 playlist via 'curl -fsSL'
    if [[ -n "$kv_pairs" ]]; then
        while IFS= read -r kv; do
            # $kv is "key=value" → transform to: "-H" "key: value"
            curl_headersArgs+=( "-H" "${kv%%=*}: ${kv#*=}" )
        done <<<"$kv_pairs"
    fi

    if (( "${#curl_headersArgs[@]}" >= 2 )); then
        log_debug "The headers which will be passed to curl:"
        for (( i=0; i<${#curl_headersArgs[@]}; i+=2 )); do
            log_debug "  [${curl_headersArgs[i]}] [${curl_headersArgs[i+1]}]";
        done
        log_debug ""  # print newline
    fi

    # fetch the m3u8 playlist (not the master) using the newly-built stream URL and cURL headers
    have curl || die "the 'curl' package is missing, please install it first"
    if { m3u8_playlist="$(curl -fsSL --compressed "${curl_headersArgs[@]}" "$stream_URL" 2>/dev/null)"; }; then
        if (( "${#m3u8_playlist}" <= 2000 )); then
            log_debug "m3u8 playlist (fetched via 'curl -fsSL'):\n[$m3u8_playlist]\n"
        else
            # if the m3u8 playlist is too long (>2000 characters), log playlist's head (1000 characters)
            # and playlist's tail (1000 characters) and then omit what is in between..
            msg="m3u8 playlist (fetched via 'curl -fsSL'):\n[${m3u8_playlist:0:1000}\n.\n.\n. *** omitting "
            msg+="$((${#m3u8_playlist} - 2000)) characters for brevity ***\n.\n.\n${m3u8_playlist: -1000}]\n"
            log_debug "$msg"
        fi
    else
        echo ""; return  # we return empty-handed from this "rigorous" method
    fi

    # detect media container from segment lines
    # fMP4 (CMAF) tends to use .m4s and often has EXT-X-MAP with .mp4 init
    if { grep --quiet -iE '\.m4s(\?|$)|#EXT-X-MAP:.*\.mp4' <<<"$m3u8_playlist"; }; then
        echo "mp4"; return
    fi

    # MPEG-2 TS segments
    if { grep --quiet -iE '\.ts(\?|$)' <<<"$m3u8_playlist"; }; then
        echo "ts"; return
    fi

    echo ""  # we return empty-handed from this "rigorous" method
}

# --- decide on file-extension: we try URL → m3u8 playlist → fallback ---
# derive_ext_from_URL (cheap heuristic, fast)
# derive_ext_from_playlist (deep inspection, accurate)
# use the fallback '.ts' if everything else fails
# That’s the right order: cheap → rigorous → fallback
extension=""
if { extension="$(derive_extension_from_URL)" && [[ -n "$extension" ]]; }; then
    log_debug "the file-extension was determined to be '.$extension' using the provided URL\n"
elif { extension="$(derive_extension_from_playlist)" && [[ -n "$extension" ]]; }; then
     log_debug "The file-extension was determined to be '.$extension' using the m3u8 playlist (fetched via 'curl -fsSL')\n"
else
    extension="ts"
    msg="Neither the provided URL nor the m3u8 playlist (fetched via 'curl -fsSL') helped "
    msg+="us to determine the file-extension, so we fall back to the default '.$extension'\n"
    log_debug "$msg"
fi

attach_file_extension()
{
    local path="$1"
    local desired_extension="$2"
    local media_extensions_list=()

    if [[ "$path" == *.* ]]; then
        # --- the path contains at least one dot, so further processing is needed ---
        # We will assume that the last dot in the path is an extension delimiter and hence what comes after it
        # is a user-provided extension (might not be true, but it doesn't really matter). We take this suspicious
        # extension and compare it against a comprehenisve list of media (audio/video) extensions and see if it
        # matches any of them. If a match occurs, we replace the user-provided media extension with our desired
        # media extension. Otherwise, we simply append our desired media extension to the end of 'path'.
        local suspicious_extension="${path##*.}"

        if [[ -r /usr/share/mime/globs ]]; then
            while IFS= read -r pattern; do
                # lines look like: "video/mp4:*.mp4" → extract "mp4"
                media_extensions_list+=( "${pattern##*.}" )
            done < <(grep -i -e "video/" -e "audio/" -- '/usr/share/mime/globs')

            log_debug "Extracted all ${#media_extensions_list[@]} media file-extensions from '/usr/share/mime/globs'\n"
        else
            # fallback list (common media extensions) — keeps script portable when /usr/share/mime/globs is absent
            media_extensions_list=( mp4 m4v m4s m3u8 webm mkv mka mov mp3 aac aiff flac oga ogg avi ts m2t m2s m4t tmf tp trp ty )
            msg="Warning: '/usr/share/mime/globs' not found, so we fall back to using the built-in incomprehensive "
            msg+="media file-extensions list\n"
            log_debug "$msg"
        fi


        for ext in "${media_extensions_list[@]}"; do
            if [[ "${suspicious_extension,,}" == "${ext,,}" ]]; then  # ${ext,,} → lowercase, ${ext^^} → uppercase
                msg="The user-provided '.$suspicious_extension' is a media file-extension, "
                msg+="and hence we will replace it with our '.$desired_extension'\n"
                log_debug "$msg"
                printf '%s.%s' "${path%.*}" "$desired_extension"
                return
            fi
        done
    fi

    # the path doesn't contain any dot, which makes our job easier (simple appending is enough)
    printf '%s.%s' "$path" "$desired_extension"
}

outputFile=$(attach_file_extension "$outputFile" "$extension")
[[ -f "$outputFile" ]] && die "the output file '$outputFile' already exists"  # check before the '.incomplete' suffix is appended
outputFile+=".incomplete" # label it as incomplete until it is complete
[[ -f "$outputFile" ]] && die "the output file '$outputFile' already exists"  # check after the '.incomplete' suffix is appended
log_debug "Name of the output media file (stays like this until download is complete):\n  [$outputFile]\n"


remove_incomplete_suffix()
{
    local inFile="$1"
    local rename_status=""

    [[ "$inFile" == *.incomplete ]] || die "the filename '$inFile' is missing the '.incomplete' suffix"
    local suffixless=${inFile%.incomplete}

    # suffixless filename should still have a file-extension
    [[ "$suffixless" == *.* ]] || die "the filename '$suffixless' is missing a file-extension"

    # this ensures no existing file gets overwritten
    local candidate_name="$suffixless"
    local n=2
    while [[ -e $candidate_name ]]; do
        candidate_name="${suffixless%.*}_{$n}.${suffixless##*.}"
        ((n++))
    done

    if { rename_status="$(mv --verbose --no-clobber -- "$inFile" "$candidate_name")"; }; then
        log_debug "\n$rename_status\n"
        # name of output media file is wrapped in a yellow ANSI color "\e[0;33m...\e[0m"
        printf '%b\n' "Download is complete, enjoy your new media file \e[0;33m'$candidate_name'\e[0m"
    fi
}


# setting --retry-max to 0 makes Streamlink fetch streams indefinitely if --retry-streams is set to a non-zero value
robust=( --retry-open 3 --retry-streams 10 --retry-max 5 ) # ensure robustness defaults for downloading HLS

SL_logLevel=( "--loglevel" )
if [[ "$DEBUG" -eq 0 ]]; then
   SL_logLevel+=( "warning" )
elif [[ "$DEBUG" -eq 1 ]]; then
    SL_logLevel+=( "info" )
elif [[ "$DEBUG" -eq 2 ]]; then
    SL_logLevel+=( "all" )
else
    die "unrecognized DEBUG=$DEBUG, please stick to DEBUG=0, DEBUG=1, or DEBUG=2" --usage
fi

SL_logFile=()
[[ -n "$logFile" ]] && SL_logFile=( "--logfile" "$logFile" )

have streamlink || die "the 'Streamlink' package is missing, please install it first"
echo "Running Streamlink → '$outputFile'"
[[ "$DEBUG" -gt 0 ]] && set -x  # all executed commands are displayed..
if { streamlink "${SL_logLevel[@]}" "${SL_logFile[@]}" "${robust[@]}" "${SL_headersArgs[@]}" "$URL" best -o "$outputFile"; }; then
    [[ "$DEBUG" -gt 0 ]] && set +x
    remove_incomplete_suffix "$outputFile" # this should gracefully remove the ".incomplete" suffix from the filename
else
    [[ "$DEBUG" -gt 0 ]] && set +x
    die "Streamlink failed to download the given media stream"
fi
