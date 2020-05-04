import { AsyncStorage } from "react-native";
import { HNStory } from "./types";
import { useState, useCallback, useEffect } from "react";

const storyKey = (story: HNStory) => `story_${story.id}`;

export const useSaveStory = (story: HNStory) => {
  const [storyItem, setStoryItem] = useState<HNStory | null>(null);

  async function getStoryItem() {
    const data = await AsyncStorage.getItem(storyKey(story));
    setStoryItem(data ? JSON.parse(data) : null);
  }

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
    getStoryItem();
  }, []);

  const save = useCallback(() => updateStoryItem(story), [story]);

  return {
    saved: storyItem !== null,
    save,
    remove: clearStoryItem,
  };
};
