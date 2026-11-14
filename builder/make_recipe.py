#!/usr/bin/env python3
"""The Builder's recipe: how to compile and link the game, taken from a
configured reference build (CMake, Ninja, compile_commands.json).

  make_recipe.py BUILD_DIR SOURCE_DIR DEPS_PREFIX KIT_DIR

Writes KIT_DIR/recipe.json:
  units    the fixed sources (src/main.cpp, the runtime's lifted_table.cpp)
  lifted   one argument list for every lifted file the player's lift makes
  link     the link of the executable
Paths become placeholders the Builder fills in: @KIT@, @WORK@, @SDK@, and per
file @SRC@ and @OBJ@; @OBJECTS@ in the link stands for every object. A path
left pointing at this machine, or into the kit at something the kit does not
hold, is an error.
"""
import json, os, re, shlex, subprocess, sys

build, source, deps, kit = (os.path.realpath(a) for a in sys.argv[1:5])
sdk = subprocess.run(['xcrun', '--show-sdk-path'], capture_output=True, text=True).stdout.strip()
places = [(os.path.realpath(p), ph) for p, ph in (
    (os.path.join(source, 'generated'), '@WORK@/generated'),
    (os.path.join(source, 'vendor/x86recomp/src'), '@KIT@/include/runtime'),
    (os.path.join(source, 'src'), '@KIT@/src'),
    (os.path.join(deps, 'include'), '@KIT@/include/deps'),
    (sdk, '@SDK@'))]
app_fw = '@KIT@/app/DarkSouls.app/Contents/Frameworks'


def rewrite(arg):
    for flag in ('-I', '-isystem', ''):
        if arg.startswith(flag) and arg[len(flag):].startswith('/'):
            path = os.path.realpath(arg[len(flag):])
            for where, ph in places:
                if path == where or path.startswith(where + '/'):
                    return flag + ph + path[len(where):]
    return arg


def check(args, what):
    for a in args:
        p = re.sub(r'^-(I|isystem|L)', '', a)
        if p.startswith('/') and not p.startswith(('/usr/', '/System/')):
            sys.exit(f'make_recipe: {what}: a path of this machine: {a}')
        if p.startswith('@KIT@') and not os.path.exists(p.replace('@KIT@', kit, 1)):
            sys.exit(f'make_recipe: {what}: not in the kit: {p}')


def compile_args(c):
    args = shlex.split(c['command'])[1:]  # the compiler is the player's xcrun clang++
    out = []
    it = iter(args)
    for a in it:
        if a == '-o':
            next(it)
            out += ['-o', '@OBJ@']
        elif a == '-c':
            next(it)
            out += ['-c', '@SRC@']
        elif a == '-isysroot':
            next(it)
            out += ['-isysroot', '@SDK@']
        elif a in ('-MD', '-MT', '-MF') or a.startswith(('-MT', '-MF', '-ffile-prefix-map=')):
            if a in ('-MT', '-MF'):
                next(it)
        else:
            out.append(rewrite(a))
    return out


units, lifted = [], None
for c in json.load(open(os.path.join(build, 'compile_commands.json'))):
    out = os.path.relpath(os.path.join(c['directory'], c.get('output', '')), build)
    f = os.path.realpath(c['file'])
    if out.startswith('CMakeFiles/darksouls_lifted.dir/generated/'):
        args = compile_args(c)
        if lifted is None:
            lifted = args
        elif args != lifted:
            sys.exit(f'make_recipe: {f} is compiled with other options than the other lifted files')
    elif out.startswith(('CMakeFiles/darksouls.dir/', 'CMakeFiles/darksouls_lifted.dir/')):
        args = compile_args(c)
        if f.endswith('.mm'):
            args = ['-x', 'objective-c++'] + args
        units.append({'src': rewrite(f), 'args': args})
if lifted is None or not units:
    sys.exit('make_recipe: no lifted code in compile_commands.json: lift and configure first')
check(lifted, 'lifted files')
for u in units:
    check(u['args'] + [u['src']], u['src'])

# The link: Ninja's command for darksouls (CMake may chain more steps after
# it with &&).
cmd = subprocess.run(['ninja', '-C', build, '-t', 'commands', 'darksouls'], capture_output=True,
                     text=True, check=True).stdout.strip().splitlines()[-1]
segments, cur = [], []
for w in shlex.split(cmd):
    if w == '&&':
        segments.append(cur)
        cur = []
    else:
        cur.append(w)
segments.append(cur)
seg = next((s for s in segments if '-o' in s and s[s.index('-o') + 1] == 'darksouls'), None)
if seg is None:
    sys.exit('make_recipe: no link step for darksouls in: ' + cmd[:300])
link, objects = [], False
it = iter(seg[1:])
for a in it:
    if a == '-o':
        next(it)
        link += ['-o', '@WORK@/game']
    elif a.endswith('.o') and a.startswith('CMakeFiles/darksouls'):
        if not objects:
            link.append('@OBJECTS@')
            objects = True
    elif a == '-isysroot':
        next(it)
        link += ['-isysroot', '@SDK@']
    elif a.startswith(('-Wl,-rpath,', '-Wl,-cache_path_lto', '-ffile-prefix-map=')):
        continue
    elif a == '-Xlinker':
        b = next(it)
        if b in ('-cache_path_lto', '-rpath'):
            next(it), next(it)
        else:
            link += ['-Xlinker', b]
    elif a.endswith('.dylib'):
        # By its install name (libavcodec.63.dylib), the file app.sh copies.
        path = a if a.startswith('/') else os.path.join(build, a)
        install = subprocess.run(['otool', '-D', path], capture_output=True, text=True,
                                 check=True).stdout.strip().splitlines()[-1]
        link.append(f'{app_fw}/{os.path.basename(install)}')
    else:
        link.append(rewrite(a))
link += ['-Wl,-rpath,@executable_path/../Frameworks', '-Wl,-cache_path_lto,@WORK@/lto-cache']
check(link, 'link')

clang = int(re.search(r'clang version (\d+)', subprocess.run(
    ['xcrun', 'clang++', '--version'], capture_output=True, text=True).stdout).group(1))
json.dump({'clang': clang, 'units': units, 'lifted': lifted, 'link': link},
          open(os.path.join(kit, 'recipe.json'), 'w'), indent=1)
print(f'make_recipe: {len(units)} fixed sources, lifted files, a link of {len(link)} arguments, clang {clang}')
