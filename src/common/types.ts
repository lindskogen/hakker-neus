export interface IDoc {
  type: string;
  content?: string;
  voidElement: boolean;
  name: string;
  attrs: {};
  children: IDoc[];
}
