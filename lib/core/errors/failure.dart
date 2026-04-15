class Failure {
  const Failure({required this.message, this.code});

  final String message;
  final String? code;
}

class CacheFailure extends Failure {
  const CacheFailure({required super.message, super.code});
}

class ApiFailure extends Failure {
  const ApiFailure({required super.message, super.code});
}
