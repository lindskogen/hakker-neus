export interface HNComment {
  id: number;
  type: string;
  by: {
    id: string;
  };
  kids?: HNComment[];
  text: string;
  timeISO: string;
}
