export interface HNComment {
  id: number;
  type: string;
  by?: {
    id: string;
  };
  kids?: HNComment[];
  text: string;
  timeISO: string;
}

export interface FlatHNComment {
  comment: HNComment;
  depth: number;
}

export interface HNStory {
  id: string;
  descendants: number;
  type: string;
  title: string;
  by?: { id: string };
  text: string;
  url?: string;
  score: number;
}
