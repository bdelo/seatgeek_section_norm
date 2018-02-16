class Normalizer
  # normalize.rb expects strings for True/False
  TRUE_STRING = "true"
  FALSE_STRING = "false"

  # Placeholder for when a section is not supplied a type
  NO_SECTION_TYPE = "no_section_type"

  # Map of section_type to shortname. Shortnames get stored in the map,
  # while the keys are manually pulled from the manifests as all possible
  # section types. Everything is in downcase for consistency.
  SECTION_TYPE_TO_SHORTNAME = {
    "top deck" => "td",
    "baseline club" => "bc",
    "loge box" => "lb",
    "club" => "c",
    "field box" => "fb",
    "right field pavilion" => "rfp",
    "reserve" => "rs",
    "left field pavilion" => "lfp",
    "dugout club" => "dc",
    "stadium club" => "sc",
  }

  # Map of known custom inputs to their associated shortname.
  # This gets manually generated from previously analyzed input. For example,
  # as a human I can see and verify that seat "FD132" should stand for "field box 132",
  # so the "fd" section type can be added to be mapped to the shortname for "field box".
  KNOWN_SECTION_INPUTS_TO_SHORTNAME = {
    "fd" => "fb",
    "pb" => "fb",
    "dg" => "dc",
    "ifb" => "fb",
    "bl" => "bc",
    "infield box" => "fb",
    "field" => "fb",
    "top" => "td",
    "infield box vip" => "fb",
    "infield box value" => "fb",
    "infield box value vip" => "fb"
  }

  def initialize
    # @section_row_map will have the following format:
    #{
    #  section_number => {
    #    section_type_shortname => {
    #      :section_id => section_id,
    #      :rows => {
    #        row_number => row_id,
    #      }
    #    },
    #  }
    #}
    @section_row_map = {}
    # @suite_map will be { section_number => section_id }
    @suite_map = {}
  end

  ## reads a manifest file
  # manifest should be a CSV containing the following columns
  #     * section_id
  #     * section_name
  #     * row_id
  #     * row_name

  # Arguments:
  #     manifest {[str]} -- /path/to/manifest
  def read_manifest(path_to_manifest)
    CSV.foreach(path_to_manifest, headers: true) do |row|
      section_id = row['section_id']
      section_name = row['section_name']
      row_id = row['row_id']
      row_name = row['row_name']

      section_number = get_section_number(section_name)
      section_type = get_section_type_from_manifest(section_name)
      row_number = get_row_number(row_name)

      if section_number.nil?
        # Probably want to log something here in real life. We dont expect
        # sections in the manifest to not have a number
        next
      end

      # row_id will be nil in the case of a suite
      if row_id.nil?
        @suite_map[section_number] = section_id
        # otherwise, this is a section with rows
      else
        @section_row_map[section_number] ||= {}
        @section_row_map[section_number][section_type] ||= {}
        @section_row_map[section_number][section_type][:section_id] = section_id
        @section_row_map[section_number][section_type][:rows] ||= {}
        @section_row_map[section_number][section_type][:rows][row_number] = row_id
      end
    end
  end

  ## normalize a single (section, row) input
  # Given a (Section, Row) input, returns (section_id, row_id, valid)
  # where
  #     section_id = int or None
  #     row_id = int or None
  #     valid = True or False

  # Arguments:
  #     section String -- section_name
  #     row String -- row_name
  def normalize(section, row)
    section_number = get_section_number(section)
    section_type = get_section_type_from_input(section)
    row_number = get_row_number(row)
    section_id = nil
    row_id = nil
    is_valid = FALSE_STRING

    if is_suite?(section, row)
      section_id = @suite_map[section_number]
      # Suites should only have a section_id and no row information
      if row.empty? && !section_id.nil?
        is_valid = TRUE_STRING
      # If there is row information, that's invalid for a suite so we want to
      # return nil for the row and not mark this as a valid input
      else
        row_id = nil
      end

    # This is the case of a section with a row
    else
      # We want to grab all of the section_types associated with this section_number first
      section_types_map = @section_row_map[section_number]
      if section_types_map.nil?
        return [nil, nil, FALSE_STRING]
      end

      # Then we want to attempt to see if our determined section_type exists in the map
      section = section_types_map[section_type]

      # If it does not, we can still assume the section_type if there is only one for
      # the section number, ie the section_number is unique across the entire venue.
      # This is a safe assumption since in that case that section_number + row combination could
      # only correspond to one possible row in the venue.
      if section.nil?
        if section_types_map.count == 1
          section = section_types_map.first[1]
        # If there are more than section_type associated with the section_number, we can't assume
        # which seat we actually want, so the input is invalid.
        else
          is_valid = FALSE_STRING
        end
      end

      if !section.nil?
        section_id = section[:section_id]
        rows = section[:rows]
        row_id = rows[row_number]
      end

      # The input is only valid if we found a corresponding section_id and row_id
      if !section_id.nil? && !row_id.nil?
        is_valid = TRUE_STRING
      end
    end

    return [section_id, row_id, is_valid]
  end

  private

  ## determine if a (section, row) input represents a suite
  # Given a (section, row) input, returns a Boolean
  # Arguments:
  #     section String - section_name
  #     row String - row_name
  # An input can apprioriately be deemed a "suite" if either the row is nil, since suites
  # don't have rows, or the section name contains the word "suite".
  # Ex. is_suite?("suite 132", "12") -> True
  #     is_suite?("132", "") -> True
  #     is_suite?("133", "A") -> False
  def is_suite?(section, row)
    if row.empty?
      return true
    elsif !section.downcase.match(/suite/).nil?
      return true
    else
      return false
    end
  end

  ## gets the section number from a (section) input
  # Given a (section_name) input returns String or nil
  # Arguments:
  #   section_name String - input section_name
  # This method strips away everything but the numbers in a section_name to determine
  # the section number. If one cannot be determined, it returns nil.
  def get_section_number(section_name)
    section_name = section_name.gsub(/[^0-9]/, '')
    section_name = section_name.split(' ')
    section_number = section_name.select{|n| !int_or_nil(n).nil?}
    if section_number.length == 1
      return section_number.first.to_i.to_s
    # Once we strip away the non numeric characters, we should only be left with one number.
    # However, if the input was something like "Section 123 143" we can't determine that section_number
    # so we return nil.
    else
      return nil
    end
  end

  ## gets the section type shortname from a (section_name)
  # Given a (section_name) input returns String
  # Arguments:
  #   section_name String - manifest section_name
  # This method strips away the section number from a manifest's section_name, and attempts to return
  # the shortname for the type. If there is no type, return the placeholder string. If SECTION_TYPE_TO_SHORTNAME
  # does not contain the section_type, just return the raw section_type. We can rely on just SECTION_TYPE_TO_SHORTNAME
  # here since presumably manifests for the same stadium should have consistent data and is not user input.
  def get_section_type_from_manifest(section_name)
    type = section_name.split(' ').select{|n| int_or_nil(n).nil?}.join(' ').downcase
    if type.empty?
      return NO_SECTION_TYPE
    else
      section_type = SECTION_TYPE_TO_SHORTNAME[type]
      if section_type.nil?
        # In reality we would probably want to log something here signaling our SECTION_TYPE_TO_SHORTNAME
        # is outdated and we're now seeing never before seen values in the manifest.
        section_type = type
      end

      return section_type
    end
  end

  # gets the section type shortname from a (section_name)
  # Given a (section_name) input returns String
  # Arguments:
  #   section_name String - input section_name
  # This method is similar to #get_section_from_manifest but has to account for section_name being user input.
  def get_section_type_from_input(section_name)
    # We first strip away all numbers and leading/trailing spaces
    section_type = section_name.gsub(/[^A-Za-z\s]/, '').split(' ').join(' ').downcase
    if section_type.empty?
      return NO_SECTION_TYPE
    end

    # Check if the wording around the section number in the input is a recognized section type
    # ex. if the section name input is 'reserve 431', see if 'reserve' is a section type
    result = get_section_type_shortname(section_type)

    # If the wording around the section number in the input is not recognized, see if any of the
    # words individually are recognized.
    # ex. input is 'all you can eat reserve 431', we should identify the section type as 'reserve'
    if result.nil?
      section_type.split(' ').each do |word|
        result = get_section_type_shortname(word)
        if !result.nil?
          break
        end
      end
    end

    # If we still can't identify the section type, just use the raw input. At this point we are going to mainly have
    # to rely on a unique section_number to identify the ticket.
    result ||= section_type
    return result
  end

  # gets the section type shortname from a (section_type)
  # Given a (section_type) input returns String or nil
  # Arguments:
  #   section_type String - input section_type
  # This method attempts to return a section type shortname that corresponds with the section_type string provided.
  # If none are found, returns nil.
  def get_section_type_shortname(section_type)
    # Build a hash of { shortname => shortname }. These could be included in KNOWN_SECTION_INPUTS_TO_SHORTNAME, but
    # this spares manually adding them as long as the shortnames used are pretty obviously mappable to a longname.
    short_names = SECTION_TYPE_TO_SHORTNAME.values.reduce({}) do |hash, short_name|
      hash[short_name] = short_name
      hash
    end

    # Return the shorname if the section_type is either the full manifest name, one of the short names, or another
    # previously seen and human verified input that maps back to a shortname.
    return SECTION_TYPE_TO_SHORTNAME[section_type] ||
      short_names[section_type] ||
      KNOWN_SECTION_INPUTS_TO_SHORTNAME[section_type]
  end

  # gets the row number from a (row_name)
  # Given a (row_name) input returns String or nil
  # Arguments:
  #   row_name String - input row_name
  # row_number is a bit of a misnomer since a row can contain letters as well.
  # This method takes an input of row_name and returns just the row_number
  # ex. get_row_number("Row 2A") -> "2A"
  def get_row_number(row_name)
    if row_name.nil?
      return nil
    end

    row_name = row_name.split(' ')
    row_number = row_name.reject{|r| r.downcase == 'row'}
    if row_number.length == 1
      row_number = row_number.first.downcase
      if !int_or_nil(row_number).nil?
        row_number = row_number.to_i.to_s
      end
      return row_number
    else
      # This is very conservative. We could take row_name.last assuming the last thing will be the row
      # most of the time, but better safe than sorry for cases where the input might be "25 rw"
      # or something
      return nil
    end
  end
end
