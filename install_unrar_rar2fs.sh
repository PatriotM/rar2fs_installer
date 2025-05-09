#!/bin/bash

# Überprüfen, ob --debug angegeben wurde
DEBUG=false
if [ "$1" = "--debug" ]; then
    DEBUG=true
    echo "Debug-Modus aktiviert: Befehle werden simuliert, aber nicht ausgeführt."
fi

# Funktion zum Ausführen oder Simulieren von Befehlen
run_cmd() {
    echo "Ausführen: $@"
    if [ "$DEBUG" = false ]; then
        "$@"
        return $?
    fi
    return 0
}

# Arbeitsverzeichnis erstellen
WORKDIR=$(mktemp -d) || { echo "Fehler: Kann temporäres Verzeichnis nicht erstellen."; exit 1; }
run_cmd cd "$WORKDIR" || exit 1

# Abhängigkeiten installieren
run_cmd apt-get -q update || exit 1
run_cmd apt-get -qy install make libfuse-dev libfuse3-dev g++ curl autoconf automake libtool gettext || exit 1

# Neueste unrar-Version ermitteln
UNRAR_VERSION=$(curl -s https://www.rarlab.com/rar_add.htm | grep -oP 'unrarsrc-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ -z "$UNRAR_VERSION" ]; then
    echo "Fehler: Kann die neueste unrar-Version nicht ermitteln."
    exit 1
fi
echo "Neueste unrar-Version: $UNRAR_VERSION"

# unrar herunterladen, kompilieren und installieren
run_cmd wget "https://www.rarlab.com/rar/unrarsrc-${UNRAR_VERSION}.tar.gz" || exit 1
run_cmd tar zxvf "unrarsrc-${UNRAR_VERSION}.tar.gz" || exit 1
run_cmd cd unrar || exit 1

# Angepasste Makefile für libunrar mit -fPIC
run_cmd cat > makefile << 'EOF'
# Makefile for UNIX - unrar

CXX=c++
CXXFLAGS=-O2 -std=c++11 -Wno-logical-op-parentheses -Wno-switch -Wno-dangling-else
LIBFLAGS=-fPIC
DEFINES=-D_FILE_OFFSET_BITS=64 -D_LARGEFILE_SOURCE -DRAR_SMP
STRIP=strip
AR=ar
LDFLAGS=-pthread
DESTDIR=/usr

##########################

COMPILE=$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(DEFINES)
LINK=$(CXX)

WHAT=UNRAR

UNRAR_OBJ=filestr.o recvol.o rs.o scantree.o qopen.o
LIB_OBJ=filestr.o scantree.o dll.o qopen.o

OBJECTS=rar.o strlist.o strfn.o pathfn.o smallfn.o global.o file.o filefn.o filcreat.o \
	archive.o arcread.o unicode.o system.o crypt.o crc.o rawread.o encname.o \
	resource.o match.o timefn.o rdwrfn.o consio.o options.o errhnd.o rarvm.o secpassword.o \
	rijndael.o getbits.o sha1.o sha256.o blake2s.o hash.o extinfo.o extract.o volume.o \
	list.o find.o unpack.o headers.o threadpool.o rs16.o cmddata.o ui.o largepage.o

# Regel für normale Objektdateien (ohne -fPIC)
.cpp.o:
	$(COMPILE) -D$(WHAT) -c $< -o $@

# Regel für Objektdateien für die Shared Library (mit -fPIC)
%.lib.o: %.cpp
	$(COMPILE) $(LIBFLAGS) -D$(WHAT) -c $< -o $@

# Liste der Objektdateien für die Shared Library (mit .lib.o Suffix)
LIB_OBJECTS=$(OBJECTS:.o=.lib.o) $(LIB_OBJ:.o=.lib.o)

all: unrar

install: install-unrar

uninstall: uninstall-unrar

clean:
	@rm -f *.bak *~
	@rm -f $(OBJECTS) $(UNRAR_OBJ) $(LIB_OBJ) $(LIB_OBJECTS)
	@rm -f unrar libunrar.*

unrar: $(OBJECTS) $(UNRAR_OBJ)
	@rm -f unrar
	$(LINK) -o unrar $(LDFLAGS) $(OBJECTS) $(UNRAR_OBJ) $(LIBS)	
	$(STRIP) unrar

sfx: WHAT=SFX_MODULE
sfx: $(OBJECTS)
	@rm -f default.sfx
	$(LINK) -o default.sfx $(LDFLAGS) $(OBJECTS)
	$(STRIP) default.sfx

lib: WHAT=RARDLL
lib: $(LIB_OBJECTS)
	@rm -f libunrar.*
	$(LINK) -shared -o libunrar.so $(LDFLAGS) $(LIB_OBJECTS)
	$(AR) rcs libunrar.a $(LIB_OBJECTS)

install-unrar:
	install -D unrar $(DESTDIR)/bin/unrar

uninstall-unrar:
	rm -f $(DESTDIR)/bin/unrar

install-lib:
	install libunrar.so $(DESTDIR)/lib
	install libunrar.a $(DESTDIR)/lib

uninstall-lib:
	rm -f $(DESTDIR)/lib/libunrar.so
EOF

run_cmd make || exit 1
run_cmd make install || exit 1
run_cmd make lib || exit 1
run_cmd make install-lib || exit 1
run_cmd cd .. || exit 1

# Neueste rar2fs-Version ermitteln
RAR2FS_VERSION=$(curl -s https://api.github.com/repos/hasse69/rar2fs/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/^v//')
if [ -z "$RAR2FS_VERSION" ]; then
    echo "Fehler: Kann die neueste rar2fs-Version nicht ermitteln."
    exit 1
fi
echo "Neueste rar2fs-Version: $RAR2FS_VERSION"

# rar2fs herunterladen, kompilieren und installieren
run_cmd wget "https://github.com/hasse69/rar2fs/releases/download/v${RAR2FS_VERSION}/rar2fs-${RAR2FS_VERSION}.tar.gz" -O "rar2fs-${RAR2FS_VERSION}.tar.gz" || exit 1
run_cmd tar zxvf "rar2fs-${RAR2FS_VERSION}.tar.gz" || exit 1
run_cmd cd "rar2fs-${RAR2FS_VERSION}" || exit 1
run_cmd autoreconf -i --force || exit 1
run_cmd ./configure --with-unrar=../unrar --with-unrar-lib=/usr/lib/ || exit 1
run_cmd make || exit 1
run_cmd make install || exit 1
run_cmd cd .. || exit 1

# Bereinigung
run_cmd cd .. || exit 1
run_cmd rm -rf "$WORKDIR" || exit 1

echo "Installation von unrar $UNRAR_VERSION und rar2fs $RAR2FS_VERSION abgeschlossen."
