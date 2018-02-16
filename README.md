This challenge was done in Ruby

The high level approach to this problem breaks down a ticket into two different types: suites and section with row. A separate map is created for each of these types. The read_manifest method determines which map the current CSV row belongs in, and maps all of the identifying information needed to the respective Seatgeek ids. The normalize method then takes an input, determines which type of ticket it is and then tries to discern the identifying information for the ticket. It then looks up that information in the map and pulls back the ids stored there.

### Suites  
The first, suites, is the much simpler of the two types. Suites do not have designated rows. This means if the row_id is `nil` in the manifest, the row section is a suite. The `#read_manifest` method builds the suites map which is a map of section_number to section_id. Section_number is just the number in the section name. For example: the section_number for "Empire Suites 132" is simply "132". We only really need this section_number for suites, since no two suites should have the same section_number.
On the other side of things, the `#normalize` method determines if the input is a suite, and if it is looks up the section_number in the suites map to find the section_id.

### Tickets with Rows
The second case is much more complicated: the ticket has a row, section_number, and section_type. Only once one is able to identify all three of these from the input can we determine if the ticket is actually valid for the stadium. We need all three because not only are row numbers not unique across different sections, but section_numbers are not necessarily unique across different section_types. For example, a stadium might have "Infield Box 100" and "Reserve 100", both of which have a section number of "100" but they are different seats. However, from the manifests given and personal experience, many times a section_number is in fact unique across all section_types and sometimes there are no section_types at all. The map for these tickets are in this format:
```ruby
{
  section_number =>
    {
      section_type =>
        {
          :section_id => section_id
          :rows =>
            {
              row_number : row_id,
            }
        },
    }
}
```
`#read_manifest` takes a row and determines the section_number in the same way as suite tickets. It then determines the section_type with a manually created dictionary based on expected manifest data and uses a short name to store in the map. If there is no section_type, it uses a placeholder signifying that. Finally, it determines the row number from the input. Each row then build the map in the above format.

`#normalize` is a much more complex method for this type of ticket. Section_number and row_number are determined in the same way as in `#read_manifest`. For the section_type, we attempt to match the words around the section number with a known quantities, that can only really be created with knowledge of previous attempted inputs by a human. If we cannot determine the section_type, we check to see if the section_number has more than one section_type associated with it. If it does not, we can assume the section_type is that one associated with the section_number, since that section_number is unique throughout the venue. This is the case where the manifest might contain a section "Reserved 100" and the input has a section name of "100". If "100" only maps to "reserved", we can assume that's the correct section. Otherwise, we're not able to accurately tell which section_type the input belongs to, so we cannot determine anything about the ticket. For example, if we have the case of "Infield Box 100" and "Reserve 100" and an input section of "100", we cannot make an assumption about which "100" section to use, and thus the input is invalid. 
