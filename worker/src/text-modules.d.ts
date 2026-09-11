declare module "*.txt" {
  const text: string;
  export default text;
}

declare module "*.png" {
  const data: ArrayBuffer;
  export default data;
}
