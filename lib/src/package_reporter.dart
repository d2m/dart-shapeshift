part of shapeshift;

class PackageReporter {
  final Map<String,DiffNode> diff = new Map<String,DiffNode>();
  final String leftPath, rightPath, out;
  IOSink io;
  String outFileName;
  
  PackageReporter(this.leftPath, this.rightPath, { this.out });
  
  void calculateDiff(String fileName) {
    File leftFile = new File("$leftPath/$fileName");
    File rightFile = new File("$rightPath/$fileName");
    JsonDiffer differ = new JsonDiffer(leftFile.readAsStringSync(), rightFile.readAsStringSync());
    differ.ensureIdentical(["name", "qualifiedName"]);
    diff[fileName] = differ.diff()
        ..metadata['qualifiedName'] = differ.leftJson['qualifiedName']
        ..metadata['name'] = differ.leftJson['name']
        ..metadata['packageName'] = differ.leftJson['packageName'];
    if (differ.leftJson['packageName'] != null) {
      outFileName = differ.leftJson['packageName'];
    }
  }

  void calculateAllDiffs() {
    List<FileSystemEntity> leftRawLs = new Directory(leftPath).listSync();
    List<String> leftLs = leftRawLs
        .where((FileSystemEntity f) => f is File)
        .map((File f) => f.path)
        .toList();

    leftLs.forEach((String file) {
      file = file.split('/').last;
      calculateDiff(file);
    });
  }

  void report() {
    Map<String,PackageSdk> diffsBySubpackage = new Map();
    diff.forEach((String file, DiffNode node) {
      if (node.metadata["packageName"] != null) {
        String subpackage = node.metadata["qualifiedName"];
        if (!diffsBySubpackage.containsKey(subpackage)) {
          diffsBySubpackage[subpackage] = new PackageSdk();
        }
        diffsBySubpackage[subpackage].package = node;
      } else {
        String subpackage = getSubpackage(node);
        if (!diffsBySubpackage.containsKey(subpackage)) {
          diffsBySubpackage[subpackage] = new PackageSdk();
        } else {
          diffsBySubpackage[subpackage].classes.add(node);
        }
      }
    });

    diffsBySubpackage.forEach((String name, PackageSdk p) {
      setIo(name);
      reportFile(p.package);
      p.classes.forEach(reportFile);
    });
  }
  
  void setIo(String packageName) {
    if (out == null) {
      io = stdout;
      return;
    }

    Directory dir = new Directory(out)..createSync(recursive: true);
    io = (new File('$out/$packageName.markdown')..createSync(recursive: true)).openWrite();
    writeMetadata(packageName);
  }
  
  void writeMetadata(String packageName) {
    io.writeln("""---
layout: page
title: $packageName
permalink: /$packageName/
---""");
  }

  void reportFile(DiffNode d) {
    new FileReporter("xxx", d, io: io).report();
  }
  
  String getSubpackage(DiffNode node) {
    return (node.metadata["qualifiedName"]).split('.')[0];
  }
}

class FileReporter {

  final String fileName;
  final DiffNode diff;
  final IOSink io;

  FileReporter(this.fileName, this.diff, { this.io });

  void report() {

    if (diff.metadata['packageName'] != null) {
      io.writeln(h1(diff.metadata['qualifiedName']));
      reportPackage();
    } else {
      io.writeln(h2(diff.metadata['name']));
      reportClass();
    }
  }

  void reportPackage() {
    // iterate over the class categories
    diff.forEachOf("classes", (k,v) {
      reportEachClassThing(k, v);
    });
  }
  
  void reportClass() {
    // iterate over the method categories
    diff.forEachOf("methods", (k,v) {
      reportEachMethodThing(k, v);
    });
    
    DiffNode variables = diff["variables"];
    if (variables.hasAdded) {
      io.writeln("New variables:\n");
      writeCodeblock(() => variables.added.values.map(variableSignature).join("\n"));
      io.writeln("---\n");
    }

    if (variables.hasRemoved) {
      io.writeln("Removed variables:\n");
      writeCodeblock(() => variables.removed.values.map(variableSignature).join("\n"));
      io.writeln("---\n");
    }

    if (variables.hasChanged) {
      variables.forEachChanged((k,v) {
        print("CHANGED: $k, $v");
      });
    }

    variables.forEach((k, variable) {
      if (variable.hasChanged) {
        variable.forEachChanged((attribute, value) {
          io.writeln("The [$attribute](#) variable changed:\n");
          io.writeln("Was: `${value[0]}`\n");
          io.writeln("Now: `${value[1]}`\n");
          io.writeln("---\n");
        });
      }
    });
  }
  
  void writeCodeblock(String x()) {
    io.write("```dart\n${x()}\n```\n\n");
  }

  String h1(String s) {
    return "$s\n${'=' * s.length}\n";
  }

  String h2(String s) {
    return "$s\n${'-' * s.length}\n";
  }

  void reportEachClassThing(String classCategory, DiffNode d) {
    d.forEachAdded((idx, klass) {
      io.writeln("New $classCategory [${klass['name']}](#)");
      io.writeln("");
    });
  }
  
  void reportEachMethodThing(String methodCategory, DiffNode d) {
    d.forEachAdded((k, v) {
      //print("New ${singularize(methodCategory)} '$k': ${pretty(v)}");
      io.writeln(
"""New ${singularize(methodCategory)} [$k](#):

```dart
${methodSignature(v as Map)}
```
---
""");
    });
    
    d.forEachRemoved((k, v) {
      //print("New ${singularize(methodCategory)} '$k': ${pretty(v)}");
      if (k == '') { k = diff.metadata['name']; }
      io.writeln(
"""Removed ${singularize(methodCategory)} [$k](#):

```dart
${methodSignature(v as Map, includeComment: false)}
```
---
""");
    });
          
    // iterate over the methods
    d.forEach((k2,v2) {
      // for a method, iterate over its attributes
      reportEachMethodAttribute(methodCategory, k2, v2);
    });
  }
  
  void reportEachMethodAttribute(String methodCategory, String method, DiffNode attributes) {
    attributes.forEach((name, att) {
      att.forEachAdded((k, v) {
        //print("The '$method' in '$methodCategory' has a new $name: '$k': ${pretty(v)}");
        String category = singularize(methodCategory);
        io.writeln("The [$method](#) ${category} has a new ${singularize(name)}: `${parameterSignature(v as Map)}`");
        io.writeln("\n---\n");
      });
    });
    
    attributes.forEachChanged((k, v) {
      io.writeln("The [$method](#) ${singularize(methodCategory)}'s `${k}` changed:\n");
      if (k == "comment") {
        String was = (v as List<String>)[0].split("\n").map((m) => "> $m").join("\n");
        io.writeln("Was:\n\n$was\n");
        String now = (v as List<String>)[1].split("\n").map((m) => "> $m").join("\n");
        io.writeln("Now:\n\n$now\n");
      } else {
        io.writeln("Was: `${(v as List)[0]}`\n");
        io.writeln("Now: `${(v as List)[1]}`");
      }
      io.writeln("\n---\n");
    });
  }
  
  // TODO: just steal this from dartdoc-viewer
  String methodSignature(Map<String,Object> method, { bool includeComment: true }) {
    String name = method['name'];
    if (name == '') { name = diff.metadata['name']; }
    String s = "${((method['return'] as List)[0] as Map)['outer']} ${name}";
    if (includeComment) {
      s = comment(method['comment']) + s;
    }
    List<String> p = new List<String>();
    (method['parameters'] as Map).forEach((k,v) {
      p.add(parameterSignature(v));
    });
    s = "$s(${p.join(', ')})";
    return s;
  }
  
  String comment(String c) {
    return c.split("\n").map((String x) => "/// $x\n").join("");
  }

  // TODO: just steal this from dartdoc-viewer
  String parameterSignature(Map<String,Object> parameter) {
    String s = "${((parameter['type'] as List)[0] as Map)['outer']} ${parameter['name']}";
    if (parameter["optional"] && parameter["named"]) {
      s = "{ $s: ${parameter['default']} }";
    }
    return s;
  }
  
  String variableSignature(Map<String,Object> variable) {
    String s = "${((variable['type'] as List)[0] as Map)['outer']} ${variable['name']};";
    if (variable['final'] == true) {
      s = "final $s";
    }
    return s;
  }
  
  String pretty(Object json) {
    return new JsonEncoder.withIndent('  ').convert(json);
  }
}

String singularize(String s) {
  // Remove trailing character. Presumably an 's'.
  return s.substring(0, s.length-1);
}

class PackageSdk {
  final List<DiffNode> classes = new List();
  DiffNode package;
}