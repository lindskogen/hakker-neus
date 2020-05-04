import AsyncStorage from "@react-native-community/async-storage";
import { HNStory } from "./types";
import { useCallback, useEffect, useState } from "react";

const storyKey = (story: HNStory) => `story_${story.id}`;

export const useSaveStory = (story: HNStory) => {
  const [storyItem, setStoryItem] = useState<HNStory | null>(null);

  function updateStoryItem(data: HNStory) {
    AsyncStorage.setItem(storyKey(story), JSON.stringify(data));
    setStoryItem(data);

    return data;
  }

  function clearStoryItem() {
    AsyncStorage.removeItem(storyKey(story));
    setStoryItem(null);
  }

  useEffect(() => {
    let cancelled = false;
    (async function () {
      const data = await AsyncStorage.getItem(storyKey(story));
      if (!cancelled) {
        setStoryItem(data ? JSON.parse(data) : null);
      }
    })();

    return () => {
      cancelled = true;
    }
  }, []);

  const save = useCallback(() => updateStoryItem(story), [story]);

  return {
    saved: storyItem !== null,
    save,
    remove: clearStoryItem,
  };
};
