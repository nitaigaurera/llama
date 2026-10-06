#!/usr/bin/env bash
# cmake_var_diff.sh - diff CMake variables/options between two git refs.
#
# Reports ADDED, REMOVED, CHANGED (default/type/help/depends), files moved,
# POSSIBLE RENAMES, and added/removed deprecation/warning messages.
# Optionally configures both refs and diffs the effective cache values.
#
# Without --repo it shallow-fetches ONLY the two given tags (depth 1, no history)
# into a temp dir. Everything it creates is removed on exit (also on Ctrl-C).
#
# Needs: bash, git, awk, sed, grep, sort, comm (+ cmake for --configure)
# Termux: pkg install git cmake

export LC_ALL=C
TAB=$(printf '\t')

usage() {
  cat <<'EOF'
Usage: cmake_var_diff.sh OLD_REF NEW_REF [options]

  --repo PATH          use an existing clone instead of fetching (read-only use)
  --url URL            where to fetch from when --repo is not given
                       (default: https://github.com/ggml-org/llama.cpp)
  --prefix A_,B_       only show variables starting with these prefixes
                       (e.g. --prefix GGML_,LLAMA_)
  --configure          also run `cmake -LAH` on both refs and diff the
                       effective cache values
  --cmake-args "..."   extra args for --configure, e.g. "-DGGML_CUDA=ON"
  -h, --help           show this help
EOF
}

repo=""; url="https://github.com/ggml-org/llama.cpp"; prefix=""; configure=0; cmake_args=(); pos=()
while [ $# -gt 0 ]; do
  case $1 in
    --repo)       repo=$2; shift 2 ;;
    --url)        url=$2; shift 2 ;;
    --prefix)     prefix=$2; shift 2 ;;
    --configure)  configure=1; shift ;;
    --cmake-args) read -ra cmake_args <<< "$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    -*)           echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
    *)            pos+=("$1"); shift ;;
  esac
done
[ ${#pos[@]} -eq 2 ] || { usage >&2; exit 2; }
old=${pos[0]}; new=${pos[1]}

prefix_re=""
[ -n "$prefix" ] && prefix_re="^($(printf '%s' "$prefix" | sed 's/,/|/g'))"

# Everything this script creates lives under $tmp (and, with --configure on a
# user-supplied --repo, temporary worktree metadata that is pruned on exit).
own_repo=1; [ -n "$repo" ] && own_repo=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/cmkdiff.XXXXXX") || exit 1
cleanup() {
  trap '' INT TERM HUP
  [ "$own_repo" -eq 0 ] && git -C "$repo" worktree list --porcelain 2>/dev/null \
    | sed -n 's/^worktree //p' | grep -F "$tmp/" \
    | while IFS= read -r w; do git -C "$repo" worktree remove --force "$w" >/dev/null 2>&1; done
  rm -rf "$tmp"
  [ "$own_repo" -eq 0 ] && git -C "$repo" worktree prune >/dev/null 2>&1
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
export GIT_TERMINAL_PROMPT=0

if [ "$own_repo" -eq 1 ]; then
  repo="$tmp/repo"
  git init -q "$repo" && git -C "$repo" remote add origin "$url" || exit 1
  for ref in "$old" "$new"; do
    echo "Fetching $ref (depth 1) from $url ..." >&2
    if git -C "$repo" fetch -q --depth 1 --no-tags origin "refs/tags/$ref:refs/tags/$ref" 2>/dev/null; then
      :
    elif git -C "$repo" fetch -q --depth 1 --no-tags origin "$ref" 2>/dev/null; then
      git -C "$repo" tag -f "$ref" FETCH_HEAD >/dev/null 2>&1 || true   # branch name
    else
      echo "Could not fetch '$ref' from $url (is it a tag, branch or commit?)" >&2
      exit 1
    fi
  done
fi

for ref in "$old" "$new"; do
  git -C "$repo" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || {
    echo "Ref not found: $ref   (try: git -C $repo tag | grep ...)" >&2; exit 1; }
done

# ---------------------------------------------------------------- awk programs
cat > "$tmp/parse.awk" <<'EOF'
function strip_comments(line,   i,c,inq,res,n) {
  inq=0; res=""; n=length(line)
  for (i=1; i<=n; i++) {
    c=substr(line,i,1)
    if (c=="\\") { res=res substr(line,i,2); i++; continue }
    if (c=="\"") inq=!inq
    if (c=="#" && !inq) break
    res=res c
  }
  return res
}
function unq(s) {
  gsub(/^[ \t\r\n]+|[ \t\r\n]+$/,"",s)
  if (length(s)>=2 && substr(s,1,1)=="\"" && substr(s,length(s),1)=="\"")
    s=substr(s,2,length(s)-2)
  return s
}
function norm(s) {
  gsub(/[ \t\r\n]+/," ",s); sub(/^ /,"",s); sub(/ $/,"",s); return s
}
function split_args(s,   i,c,cur,inq,depth,L) {
  split("",args); nargs=0; cur=""; inq=0; depth=0; L=length(s)
  for (i=1; i<=L; i++) {
    c=substr(s,i,1)
    if (c=="\\" && i<L) { cur=cur substr(s,i,2); i++; continue }
    if (c=="\"") { inq=!inq; cur=cur c }
    else if (!inq && c=="(") { depth++; cur=cur c }
    else if (!inq && c==")") { depth--; cur=cur c }
    else if (!inq && depth==0 && (c==" "||c=="\t"||c=="\n"||c=="\r")) {
      if (cur!="") { args[++nargs]=cur; cur="" }
    } else cur=cur c
  }
  if (cur!="") args[++nargs]=cur
}
function join_range(a,b,   i,r) {
  r=""
  for (i=a; i<=b; i++) r = r (r==""?"":" ") unq(args[i])
  return norm(r)
}
function emit(name,type,def,doc,dep) {
  printf "D\t%s\t%s\t%s\t%s\t%s\t%s\n", name,type,def,doc,dep,file
}
function handle(cmd, body,   i,k,mode,name,def,doc,dep,type) {
  split_args(body)
  if (nargs<1) return
  if (cmd=="option" || cmd=="cmake_dependent_option") {
    name=args[1]
    doc=(nargs>=2)?norm(unq(args[2])):""
    def=(nargs>=3)?norm(unq(args[3])):"OFF"
    dep=(cmd=="cmake_dependent_option" && nargs>=4)?norm(unq(args[4])):""
    emit(name,"BOOL",def,doc,dep)
  } else if (cmd=="set") {
    k=0
    for (i=2; i<=nargs; i++) if (toupper(args[i])=="CACHE") { k=i; break }
    if (k) {
      type=(nargs>=k+1)?args[k+1]:""
      doc=(nargs>=k+2)?norm(unq(args[k+2])):""
      emit(args[1],type,join_range(2,k-1),doc,"")
    }
  } else if (cmd=="message") {
    mode=toupper(unq(args[1]))
    if (mode=="DEPRECATION"||mode=="WARNING"||mode=="AUTHOR_WARNING"||
        mode=="FATAL_ERROR"||mode=="SEND_ERROR")
      printf "M\t%s\t%s\n", mode, substr(join_range(2,nargs),1,220)
  }
}
{ text = text strip_comments($0) "\n" }
END {
  lt=tolower(text); pos=1; Lt=length(text)
  while (pos<=Lt) {
    rest=substr(lt,pos)
    if (!match(rest,/(^|[^a-z0-9_.])(option|cmake_dependent_option|set|message)[ \t\n]*\(/)) break
    m=substr(rest,RSTART,RLENGTH)
    argstart=pos+RSTART-1+RLENGTH
    sub(/^[^a-z]/,"",m); sub(/[ \t\n]*\($/,"",m)
    depth=1; inq=0; j=argstart
    while (j<=Lt && depth>0) {
      c=substr(text,j,1)
      if (c=="\\") { j+=2; continue }
      if (c=="\"") inq=!inq
      else if (!inq) { if (c=="(") depth++; else if (c==")") depth-- }
      j++
    }
    handle(m, substr(text,argstart,j-1-argstart))
    pos=j
  }
}
EOF

cat > "$tmp/fmt.awk" <<'EOF'
BEGIN { FS="\t" }
{
  printf "  %s %s  default=%s  (%s)%s\n", sign, $1, $3, $6, ($5!="" ? "  [depends: " $5 "]" : "")
  if ($4!="") printf "      \"%s\"\n", $4
}
EOF

cat > "$tmp/changed.awk" <<'EOF'
BEGIN { FS="\t"; F[1]="type"; F[2]="default"; F[3]="doc"; F[4]="depends" }
function flush(   i,a,b) {
  if (name=="") return
  print "  " name
  if (no==1 && nn==1) {
    split(ol[1],a,"\t"); split(nl[1],b,"\t")
    for (i=1; i<=4; i++)
      if (a[i]!=b[i]) printf "      %s: \047%s\047  ->  \047%s\047\n", F[i], a[i], b[i]
  } else {
    for (i=1; i<=no; i++) { s=ol[i]; gsub(/\t/," | ",s); print "      - " s }
    for (i=1; i<=nn; i++) { s=nl[i]; gsub(/\t/," | ",s); print "      + " s }
  }
  no=0; nn=0
}
{
  if ($2!=name) { flush(); name=$2 }
  rec=$3 "\t" $4 "\t" $5 "\t" $6
  if ($1=="O") ol[++no]=rec; else nl[++nn]=rec
}
END { flush() }
EOF

cat > "$tmp/moved.awk" <<'EOF'
BEGIN { FS="\t" }
function flush() {
  if (name=="") return
  print "  " name ": " o "  ->  " n
  o=""; n=""
}
{
  if ($2!=name) { flush(); name=$2 }
  if ($1=="O") o = o (o==""?"":", ") $3; else n = n (n==""?"":", ") $3
}
END { flush() }
EOF

cat > "$tmp/rename.awk" <<'EOF'
BEGIN { FS="\t" }
function suf(n,   p) { p=index(n,"_"); return p ? substr(n,p+1) : "" }
NR==FNR { rd[$1]=$4; next }
{ ad[$1]=$4 }
END {
  for (r in rd) for (a in ad) {
    why=""
    if (rd[r]!="" && rd[r]==ad[a]) why="same help text"
    else if (length(suf(r))>=3 && suf(r)==suf(a)) why="same name suffix"
    if (why!="") print r "\t" a "\t" why
  }
}
EOF

cat > "$tmp/effdiff.awk" <<'EOF'
BEGIN { FS="\t" }
NR==FNR { ot[$1]=$2; ov[$1]=$3; next }
{ seen[$1]=1
  if (!($1 in ov)) printf "  + %s = %s  (%s)\n", $1, $3, $2
  else if (ov[$1]!=$3) printf "  ~ %s: \047%s\047 -> \047%s\047\n", $1, ov[$1], $3 }
END { for (k in ov) if (!(k in seen)) printf "  - %s = %s  (%s)\n", k, ov[k], ot[k] }
EOF

# ------------------------------------------------------------------ extraction
extract() {  # ref outprefix
  local ref=$1 out=$2 f
  : > "$out.raw"; : > "$out.text"
  git -C "$repo" ls-tree -r --name-only "$ref" \
    | grep -E '(^|/)CMakeLists\.txt$|\.cmake$' > "$out.files"
  while IFS= read -r f; do
    git -C "$repo" show "$ref:$f" > "$tmp/cur" 2>/dev/null || continue
    sed 's/#.*//' "$tmp/cur" >> "$out.text"
    awk -v file="$f" -f "$tmp/parse.awk" "$tmp/cur" >> "$out.raw"
  done < "$out.files"
  awk -F'\t' -v re="$prefix_re" \
    '$1=="D" && (re=="" || $2 ~ re) { sub(/^D\t/,""); print }' "$out.raw" | sort -u > "$out.decl"
  awk -F'\t' '$1=="M" { sub(/^M\t/,""); print }' "$out.raw" | sort -u > "$out.msgs"
}

extract "$old" "$tmp/old"
extract "$new" "$tmp/new"

tag() { awk -v t="$1" '{ print t "\t" $0 }'; }
only_in() {  # file-of-names, stdin filtered to lines whose field1 is in names
  awk -F'\t' 'NR==FNR { a[$1]; next } $1 in a' "$1" -
}
count() { wc -l < "$1" | tr -d ' '; }

cut -f1 "$tmp/old.decl" | sort -u > "$tmp/old.names"
cut -f1 "$tmp/new.decl" | sort -u > "$tmp/new.names"
comm -13 "$tmp/old.names" "$tmp/new.names" > "$tmp/added.names"
comm -23 "$tmp/old.names" "$tmp/new.names" > "$tmp/removed.names"
comm -12 "$tmp/old.names" "$tmp/new.names" > "$tmp/common.names"

cut -f1-5 "$tmp/old.decl" | sort -u > "$tmp/old.sig"
cut -f1-5 "$tmp/new.decl" | sort -u > "$tmp/new.sig"
{ comm -23 "$tmp/old.sig" "$tmp/new.sig" | only_in "$tmp/common.names" | tag O
  comm -13 "$tmp/old.sig" "$tmp/new.sig" | only_in "$tmp/common.names" | tag N
} | sort -s -t "$TAB" -k2,2 > "$tmp/changed.tag"
cut -f2 "$tmp/changed.tag" | sort -u > "$tmp/changed.names"
comm -23 "$tmp/common.names" "$tmp/changed.names" > "$tmp/unchanged.names"

cut -f1,6 "$tmp/old.decl" | sort -u > "$tmp/old.nf"
cut -f1,6 "$tmp/new.decl" | sort -u > "$tmp/new.nf"
{ comm -23 "$tmp/old.nf" "$tmp/new.nf" | only_in "$tmp/unchanged.names" | tag O
  comm -13 "$tmp/old.nf" "$tmp/new.nf" | only_in "$tmp/unchanged.names" | tag N
} | sort -s -t "$TAB" -k2,2 > "$tmp/moved.tag"

n_add=$(count "$tmp/added.names"); n_rem=$(count "$tmp/removed.names")
n_chg=$(count "$tmp/changed.names"); n_mov=$(cut -f2 "$tmp/moved.tag" | sort -u | wc -l | tr -d ' ')

# ---------------------------------------------------------------------- report
echo "# CMake variable diff: $old -> $new"
echo "# declared: $(count "$tmp/old.names") -> $(count "$tmp/new.names")  |  +$n_add  -$n_rem  ~$n_chg  moved:$n_mov"
echo

echo "== ADDED ($n_add) =="
awk -F'\t' 'NR==FNR { a[$1]; next } $1 in a' "$tmp/added.names" "$tmp/new.decl" \
  | awk -v sign=+ -f "$tmp/fmt.awk"

echo
echo "== REMOVED ($n_rem) =="
while IFS= read -r n; do
  [ -z "$n" ] && continue
  detail=$(awk -F'\t' -v n="$n" '$1==n { printf "default=%s  (%s)%s", $3, $6, ($5!="" ? "  [depends: " $5 "]" : ""); exit }' "$tmp/old.decl")
  flag=""
  grep -qwF -- "$n" "$tmp/new.text" && flag="   <-- still referenced in new tree (deprecated/renamed?)"
  echo "  - $n  $detail$flag"
done < "$tmp/removed.names"

echo
echo "== CHANGED ($n_chg) =="
awk -f "$tmp/changed.awk" "$tmp/changed.tag"

echo
echo "== DECLARATION FILE CHANGED, DEFINITION IDENTICAL ($n_mov) =="
awk -f "$tmp/moved.awk" "$tmp/moved.tag"

echo
echo "== POSSIBLE RENAMES (removed -> added) =="
awk -F'\t' 'NR==FNR { a[$1]; next } $1 in a' "$tmp/removed.names" "$tmp/old.decl" > "$tmp/removed.decl"
awk -F'\t' 'NR==FNR { a[$1]; next } $1 in a' "$tmp/added.names"   "$tmp/new.decl" > "$tmp/added.decl"
awk -f "$tmp/rename.awk" "$tmp/removed.decl" "$tmp/added.decl" | sort -u > "$tmp/renames"
if [ -s "$tmp/renames" ]; then
  awk -F'\t' '{ printf "  %s  ->  %s   (%s)\n", $1, $2, $3 }' "$tmp/renames"
else
  echo "  (none detected)"
fi

echo
echo "== DEPRECATION / WARNING / ERROR MESSAGES =="
comm -13 "$tmp/old.msgs" "$tmp/new.msgs" | awk -F'\t' '{ printf "  + [%s] %s\n", $1, $2 }'
comm -23 "$tmp/old.msgs" "$tmp/new.msgs" | awk -F'\t' '{ printf "  - [%s] %s\n", $1, $2 }'
cmp -s "$tmp/old.msgs" "$tmp/new.msgs" && echo "  (no change)"

# ------------------------------------------------------------------- configure
effective() {  # ref outfile
  local ref=$1 out=$2 wt="$tmp/wt_$RANDOM" rc=0
  if ! git -C "$repo" worktree add -q --detach "$wt" "$ref" >/dev/null 2>&1; then
    echo "  (could not create worktree for $ref)" >&2; : > "$out"; return 1
  fi
  cmake -S "$wt" -B "$wt/build" -LAH "${cmake_args[@]}" > "$out.log" 2>&1 || rc=$?
  sed -n 's/^\([A-Za-z0-9_]*\):\([A-Za-z]*\)=\(.*\)$/\1\t\2\t\3/p' "$out.log" \
    | sed "s#$wt#<SRC>#g" \
    | awk -F'\t' -v re="$prefix_re" 're=="" || $1 ~ re' | sort -u > "$out"
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
  return $rc
}

if [ "$configure" -eq 1 ]; then
  command -v cmake >/dev/null || { echo "cmake not found (pkg install cmake)" >&2; exit 1; }
  echo
  echo "== EFFECTIVE CACHE VALUES (cmake -LAH; args: ${cmake_args[*]:-defaults}) =="
  effective "$old" "$tmp/old.eff" || echo "  (warning: cmake failed for $old; results may be partial, see log)"
  effective "$new" "$tmp/new.eff" || echo "  (warning: cmake failed for $new; results may be partial, see log)"
  awk -F'\t' -f "$tmp/effdiff.awk" "$tmp/old.eff" "$tmp/new.eff" | sort -k2
fi
