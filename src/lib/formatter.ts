import { AllHtmlEntities } from "html-entities";

const htmlEntities = new AllHtmlEntities();

export const decodeHTMLEntities = (title: string): string =>
  htmlEntities.decode(title);
