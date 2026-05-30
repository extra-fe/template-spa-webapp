import { Request } from 'express';

/** Auth0 が発行する JWT のうち本アプリで参照するクレーム */
export interface Auth0JwtPayload {
  sub: string;
  email?: string;
  roles?: string[];
}

/** ガード通過後に request.user へ格納される認証ユーザー情報 */
export interface AuthUser {
  sub: string;
  email?: string;
  name?: string;
  roles?: string[];
}

/** user を保持しうる Express リクエスト */
export type AuthenticatedRequest = Request & { user?: AuthUser };
