// public/ 자산을 Vite base 경로에 맞춰 참조한다. dev('/')와
// 배포('/auto-lock/') 양쪽에서 이미지가 깨지지 않게 BASE_URL을 붙인다.
export function asset(path) {
  const base = import.meta.env.BASE_URL // '/' 또는 '/auto-lock/'
  return base.replace(/\/$/, '') + '/' + path.replace(/^\//, '')
}
