/**
 * Result.ets
 * 分层：common / 基础类型
 *
 * 职责：提供一个轻量的 Result<T> 包装，用于在领域层/数据层以"值"的方式
 *       传递成功或失败，避免到处 try/catch 与异常穿透。
 *
 * 设计：
 *  - ok = true 时 value 有效；ok = false 时 error 有效。
 *  - 提供 map / getOrElse 等便捷方法，鼓励函数式处理。
 *  - 这是不可变(immutable)结果对象，创建后不应修改。
 */
export class Result<T> {
  /** 是否成功。 */
  readonly ok: boolean;
  /** 成功时的值（失败时为 undefined）。 */
  readonly value?: T;
  /** 失败时的错误（成功时为 undefined）。 */
  readonly error?: Error;

  private constructor(ok: boolean, value?: T, error?: Error) {
    this.ok = ok;
    this.value = value;
    this.error = error;
  }

  /** 构造成功结果。 */
  static success<T>(value: T): Result<T> {
    return new Result<T>(true, value, undefined);
  }

  /** 构造失败结果。可传入 Error 或字符串消息。 */
  static failure<T>(error: Error | string): Result<T> {
    const err: Error = typeof error === 'string' ? new Error(error) : error;
    return new Result<T>(false, undefined, err);
  }

  /**
   * 以受检方式执行一个同步函数并捕获异常为 Result。
   */
  static run<T>(block: () => T): Result<T> {
    try {
      return Result.success(block());
    } catch (e) {
      return Result.failure(e as Error);
    }
  }

  /**
   * 以受检方式执行一个异步函数并捕获异常为 Result。
   */
  static async runAsync<T>(block: () => Promise<T>): Promise<Result<T>> {
    try {
      const v: T = await block();
      return Result.success(v);
    } catch (e) {
      return Result.failure(e as Error);
    }
  }

  /** 成功时映射值；失败时透传错误。 */
  map<R>(transform: (value: T) => R): Result<R> {
    if (this.ok && this.value !== undefined) {
      return Result.success(transform(this.value));
    }
    return Result.failure<R>(this.error ?? new Error('unknown error'));
  }

  /** 取值，失败时返回兜底值。 */
  getOrElse(fallback: T): T {
    return this.ok && this.value !== undefined ? this.value : fallback;
  }

  /** 取值，失败时返回 undefined。 */
  getOrNull(): T | undefined {
    return this.ok ? this.value : undefined;
  }
}
