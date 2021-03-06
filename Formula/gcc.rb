class Gcc < Formula
  desc "GNU compiler collection"
  homepage "https://gcc.gnu.org/"
  url "https://ftp.gnu.org/gnu/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz"
  mirror "https://ftpmirror.gnu.org/gcc/gcc-8.3.0/gcc-8.3.0.tar.xz"
  sha256 "64baadfe6cc0f4947a84cb12d7f0dfaf45bb58b7e92461639596c21e02d97d2c"
  head "https://gcc.gnu.org/git/gcc.git"

  bottle do
    sha256 "1b11086a7e1732cb6077a2e96889ab847226308a76cb5acfaacec98a5c76567f" => :mojave
    sha256 "c0695cd4808438b1eb3c98ed2c96f8f8806c920fce739ac4acf42789c9aede67" => :high_sierra
    sha256 "49843c479e2ac3464d9022c916d109a7c0f89e7a5a6046f934c0b18e25aa54e4" => :sierra
  end

  patch :DATA

  # The bottles are built on systems with the CLT installed, and do not work
  # out of the box on Xcode-only systems due to an incorrect sysroot.
  pour_bottle? do
    reason "The bottle needs the Xcode CLT to be installed."
    satisfy { MacOS::CLT.installed? }
  end

  depends_on "gmp"
  depends_on "isl"
  depends_on "libmpc"
  depends_on "mpfr"

  # GCC bootstraps itself, so it is OK to have an incompatible C++ stdlib
  cxxstdlib_check :skip

  def version_suffix
    if build.head?
      "HEAD"
    else
      version.to_s.slice(/\d/)
    end
  end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete "LD"

    # We avoiding building:
    #  - Ada, which requires a pre-existing GCC Ada compiler to bootstrap
    #  - Go, currently not supported on macOS
    #  - BRIG
    languages = %w[c c++ objc obj-c++ fortran]

    osmajor = `uname -r`.chomp
    pkgversion = "Homebrew GCC #{pkg_version} #{build.used_options*" "}".strip

    args = %W[
      --build=x86_64-apple-darwin#{osmajor}
      --prefix=#{prefix}
      --libdir=#{lib}/gcc/#{version_suffix}
      --disable-nls
      --enable-checking=release
      --enable-languages=#{languages.join(",")}
      --program-suffix=-#{version_suffix}
      --with-gmp=#{Formula["gmp"].opt_prefix}
      --with-mpfr=#{Formula["mpfr"].opt_prefix}
      --with-mpc=#{Formula["libmpc"].opt_prefix}
      --with-isl=#{Formula["isl"].opt_prefix}
      --with-system-zlib
      --with-pkgversion=#{pkgversion}
      --with-bugurl=https://github.com/Homebrew/homebrew-core/issues
    ]

    # Xcode 10 dropped 32-bit support
    args << "--disable-multilib" if DevelopmentTools.clang_build_version >= 1000

    # Ensure correct install names when linking against libgcc_s;
    # see discussion in https://github.com/Homebrew/legacy-homebrew/pull/34303
    inreplace "libgcc/config/t-slibgcc-darwin", "@shlib_slibdir@", "#{HOMEBREW_PREFIX}/lib/gcc/#{version_suffix}"

    mkdir "build" do
      if !MacOS::CLT.installed?
        # For Xcode-only systems, we need to tell the sysroot path
        args << "--with-native-system-header-dir=/usr/include"
        args << "--with-sysroot=#{MacOS.sdk_path}"
      elsif MacOS.version >= :mojave
        # System headers are no longer located in /usr/include
        args << "--with-native-system-header-dir=/usr/include"
        args << "--with-sysroot=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
      end

      system "../configure", *args

      # Use -headerpad_max_install_names in the build,
      # otherwise updated load commands won't fit in the Mach-O header.
      # This is needed because `gcc` avoids the superenv shim.
      system "make", "BOOT_LDFLAGS=-Wl,-headerpad_max_install_names"
      system "make", "install"

      bin.install_symlink bin/"gfortran-#{version_suffix}" => "gfortran"
    end

    # Handle conflicts between GCC formulae and avoid interfering
    # with system compilers.
    # Rename man7.
    Dir.glob(man7/"*.7") { |file| add_suffix file, version_suffix }
    # Even when we disable building info pages some are still installed.
    info.rmtree
  end

  def add_suffix(file, suffix)
    dir = File.dirname(file)
    ext = File.extname(file)
    base = File.basename(file, ext)
    File.rename file, "#{dir}/#{base}-#{suffix}#{ext}"
  end

  test do
    (testpath/"hello-c.c").write <<~EOS
      #include <stdio.h>
      int main()
      {
        puts("Hello, world!");
        return 0;
      }
    EOS
    system "#{bin}/gcc-#{version_suffix}", "-o", "hello-c", "hello-c.c"
    assert_equal "Hello, world!\n", `./hello-c`

    (testpath/"hello-cc.cc").write <<~EOS
      #include <iostream>
      int main()
      {
        std::cout << "Hello, world!" << std::endl;
        return 0;
      }
    EOS
    system "#{bin}/g++-#{version_suffix}", "-o", "hello-cc", "hello-cc.cc"
    assert_equal "Hello, world!\n", `./hello-cc`

    (testpath/"test.f90").write <<~EOS
      integer,parameter::m=10000
      real::a(m), b(m)
      real::fact=0.5

      do concurrent (i=1:m)
        a(i) = a(i) + fact*b(i)
      end do
      write(*,"(A)") "Done"
      end
    EOS
    system "#{bin}/gfortran", "-o", "test", "test.f90"
    assert_equal "Done\n", `./test`
  end
end
__END__
diff -r -u gcc-8.3.0/fixincludes/fixincl.x gcc-8.3.0-patch/fixincludes/fixincl.x
--- gcc-8.3.0/fixincludes/fixincl.x	2018-02-23 01:12:26.000000000 +0900
+++ gcc-8.3.0-patch/fixincludes/fixincl.x	2019-04-11 12:37:25.000000000 +0900
@@ -3222,6 +3222,44 @@
 
 /* * * * * * * * * * * * * * * * * * * * * * * * * *
  *
+ *  Description of Darwin_Ucred__Atomic fix
+ */
+tSCC zDarwin_Ucred__AtomicName[] =
+     "darwin_ucred__Atomic";
+
+/*
+ *  File name selection pattern
+ */
+tSCC zDarwin_Ucred__AtomicList[] =
+  "sys/ucred.h\0";
+/*
+ *  Machine/OS name selection pattern
+ */
+tSCC* apzDarwin_Ucred__AtomicMachs[] = {
+        "*-*-darwin18*",
+        (const char*)NULL };
+
+/*
+ *  content selection pattern - do fix if pattern found
+ */
+tSCC zDarwin_Ucred__AtomicSelect0[] =
+       "_Atomic";
+
+#define    DARWIN_UCRED__ATOMIC_TEST_CT  1
+static tTestDesc aDarwin_Ucred__AtomicTests[] = {
+  { TT_EGREP,    zDarwin_Ucred__AtomicSelect0, (regex_t*)NULL }, };
+
+/*
+ *  Fix Command Arguments for Darwin_Ucred__Atomic
+ */
+static const char* apzDarwin_Ucred__AtomicPatch[] = {
+    "wrap",
+    "# define _Atomic volatile\n",
+    "# undef _Atomic\n",
+    (char*)NULL };
+
+/* * * * * * * * * * * * * * * * * * * * * * * * * *
+ *
  *  Description of Dec_Intern_Asm fix
  */
 tSCC zDec_Intern_AsmName[] =
@@ -10099,9 +10137,9 @@
  *
  *  List of all fixes
  */
-#define REGEX_COUNT          287
+#define REGEX_COUNT          288
 #define MACH_LIST_SIZE_LIMIT 187
-#define FIX_COUNT            249
+#define FIX_COUNT            250
 
 /*
  *  Enumerate the fixes
@@ -10183,6 +10221,7 @@
     DARWIN_STDINT_5_FIXIDX,
     DARWIN_STDINT_6_FIXIDX,
     DARWIN_STDINT_7_FIXIDX,
+    DARWIN_UCRED__ATOMIC_FIXIDX,
     DEC_INTERN_ASM_FIXIDX,
     DJGPP_WCHAR_H_FIXIDX,
     ECD_CURSOR_FIXIDX,
@@ -10739,6 +10778,11 @@
      DARWIN_STDINT_7_TEST_CT, FD_MACH_ONLY | FD_SUBROUTINE,
      aDarwin_Stdint_7Tests,   apzDarwin_Stdint_7Patch, 0 },
 
+  {  zDarwin_Ucred__AtomicName,    zDarwin_Ucred__AtomicList,
+     apzDarwin_Ucred__AtomicMachs,
+     DARWIN_UCRED__ATOMIC_TEST_CT, FD_MACH_ONLY | FD_SUBROUTINE,
+     aDarwin_Ucred__AtomicTests,   apzDarwin_Ucred__AtomicPatch, 0 },
+
   {  zDec_Intern_AsmName,    zDec_Intern_AsmList,
      apzDec_Intern_AsmMachs,
      DEC_INTERN_ASM_TEST_CT, FD_MACH_ONLY,
diff -r -u gcc-8.3.0/fixincludes/inclhack.def gcc-8.3.0-patch/fixincludes/inclhack.def
--- gcc-8.3.0/fixincludes/inclhack.def	2018-02-23 01:12:26.000000000 +0900
+++ gcc-8.3.0-patch/fixincludes/inclhack.def	2019-04-11 12:37:59.000000000 +0900
@@ -1592,6 +1592,19 @@
 		"#define UINTMAX_C(v) (v ## ULL)";
 };
 
+/*  XCode 10.2 <sys/ucred.h> uses the C _Atomic keyword in C++ code.
+*/
+fix = {
+    hackname  = darwin_ucred__Atomic;
+    mach      = "*-*-darwin18*";
+    files     = sys/ucred.h;
+    select    = "_Atomic";
+    c_fix     = wrap;
+    c_fix_arg = "# define _Atomic volatile\n";
+    c_fix_arg = "# undef _Atomic\n";
+    test_text = "_Atomic";
+};
+
 /*
  *  Fix <c_asm.h> on Digital UNIX V4.0:
  *  It contains a prototype for a DEC C internal asm() function,
