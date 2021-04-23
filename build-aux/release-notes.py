#!/usr/bin/python3

import gi, sys, os
gi.require_version ('Ggit', '1.0')
from gi.repository import Gio, Ggit

class ReleaseMaker:
    __changes_list = []
    __translations_list = []
    __contributors_list = []

    def __init__ (self, repo_path):
        Ggit.init ()

        repo_file = Gio.File.new_for_path (repo_path)
        self.repo = Ggit.Repository.open (repo_file)
        rev_walker = Ggit.RevisionWalker.new (self.repo)
        rev_walker.set_sort_mode ((Ggit.SortMode.TIME |
                                   Ggit.SortMode.TOPOLOGICAL))
        head = Ggit.Repository.get_head (self.repo)
        oid = Ggit.Ref.get_target (head)
        rev_walker.push (oid)

        while (oid := rev_walker.next ()) is not None:
            commit = self.repo.lookup (oid, Ggit.Commit)
            message = commit.get_message ()
            if message.startswith ("Post-release version bump"):
                break;

            message_summary = message.partition ("\n")[0]
            if not self.__is_translation_commit (message_summary):
                self.__changes_list.append (message_summary)
            else:
                translation_summary = message_summary.split ()
                translation_name = " ".join (translation_summary[1:-1])

                if translation_name not in self.__translations_list:
                    self.__translations_list.append (translation_name)

            signature = commit.get_author ()
            author_signature = ("%s <%s>" % (signature.get_name (),
                                             signature.get_email ()))
            if author_signature not in self.__contributors_list:
                self.__contributors_list.append (author_signature)

    @staticmethod
    def __is_translation_commit (message):
        return (message.startswith ("Update ") and
            message.endswith ("translation"))

    def get_last_tag (self):
        return self.repo.list_tags ()[0]

    def get_changes_list (self):
        return self.__changes_list

    def get_translations_list (self, sort = True):
        if sort:
            return sorted (self.__translations_list)

        return self.__translations_list

    def get_contributors_list (self, sort = True):
        if sort:
            return sorted (self.__contributors_list)

        return self.__contributors_list

if __name__ == "__main__":
    if len (sys.argv) != 2:
        print ("Usage ./release-notes.py REPOSITORY_PATH")
        sys.exit (0)

    repo_path = sys.argv[1]
    if not os.path.exists (repo_path):
        print ("Invalid repository path '%s'" % repo_path)
        sys.exit (0)

    release_maker = ReleaseMaker (repo_path)
    print ("Changes since %s\n" % release_maker.get_last_tag ())

    for change_summary in release_maker.get_changes_list ():
        print ("  - %s" % change_summary)

    print ("  - Added/updated/fixed translations:")
    for translation_name in release_maker.get_translations_list ():
        print ("    - %s"% translation_name)

    print ("\nAll contributors to this release:\n")

    for author_signature in release_maker.get_contributors_list ():
        print (author_signature)
