import Darwin

enum PrivateSymbol {
  static func function<Function>(named name: String, as _: Function.Type) -> Function? {
    dlsym(dlopen(nil, RTLD_NOW), name).map { unsafeBitCast($0, to: Function.self) }
  }
}
