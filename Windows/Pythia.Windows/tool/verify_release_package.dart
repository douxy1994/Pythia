import 'dart:io';

import 'package:pythia_windows/core/release_package_verifier.dart';

Future<void> main(List<String> arguments) async {
  final packagePath =
      arguments.isEmpty ? 'build/windows/x64/runner/Release' : arguments.first;
  final root = Directory(packagePath);
  final issues = await ReleasePackageVerifier().verify(root);

  if (issues.isEmpty) {
    stdout.writeln('Pythia release package verification passed: ${root.path}');
    return;
  }

  stderr.writeln('Pythia release package verification failed: ${root.path}');
  for (final issue in issues) {
    stderr.writeln('- $issue');
  }
  exitCode = 1;
}
